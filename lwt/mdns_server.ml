(*
 * Copyright (c) 2005-2012 Anil Madhavapeddy <anil@recoil.org>
 * Copyright (c) 2013 David Sheets <sheets@alum.mit.edu>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Lwt
open Printf

module DR = Dns.RR
module DP = Dns.Packet
module DS = Dns.Protocol.Server
module DQ = Dns.Query
module H = Dns.Hashcons

type ip_endpoint = Ipaddr.V4.t * int

type unique = Unique | Shared

module type TRANSPORT = sig
  val alloc : unit -> Dns.Buf.t
  val write : ip_endpoint -> Dns.Buf.t -> unit Lwt.t
  val sleep : float -> unit Lwt.t
end

let multicast_ip = Ipaddr.V4.of_string_exn "224.0.0.251"

let sentinel = DR.Unknown (0, [])

let filter_out_known rr known =
  match (rr, known) with

  | (DR.A l, DP.A k) ->
    let lf = List.filter (fun ip -> k <> ip) l
    in
    if lf <> [] then DR.A lf else sentinel

  | (DR.AAAA l, DP.AAAA k) ->
    let lf = List.filter (fun ip -> k <> ip) l
    in
    if lf <> [] then DR.AAAA lf else sentinel

  | (DR.CNAME l, DP.CNAME k) ->
    let lf = List.filter (fun d -> d.DR.owner.H.node <> k) l
    in
    if lf <> [] then DR.CNAME lf else sentinel

  | (DR.MB l, DP.MB k) ->
    let lf = List.filter (fun d -> d.DR.owner.H.node <> k) l
    in
    if lf <> [] then DR.MB lf else sentinel

  | (DR.MG l, DP.MB k) ->
    let lf = List.filter (fun d -> d.DR.owner.H.node <> k) l
    in
    if lf <> [] then DR.MG lf else sentinel

  | (DR.MR l, DP.MR k) ->
    let lf = List.filter (fun d -> d.DR.owner.H.node <> k) l
    in
    if lf <> [] then DR.MR lf else sentinel

  | (DR.NS l, DP.NS k) ->
    let lf = List.filter (fun d -> d.DR.owner.H.node <> k) l
    in
    if lf <> [] then DR.NS lf else sentinel

  (* SOA not relevant *)
  | (DR.WKS l, DP.WKS (ka, kp, kb)) ->
    let lf = List.filter (fun (address, protocol, bitmap) ->
        address <> ka || protocol <> kp || bitmap.H.node <> kb) l
    in
    if lf <> [] then DR.WKS lf else sentinel

  | (DR.PTR l, DP.PTR k) ->
    let lf = List.filter (fun d -> d.DR.owner.H.node <> k) l
    in
    if lf <> [] then DR.PTR lf else sentinel

  | (DR.HINFO l, DP.HINFO (kcpu, kos)) ->
    let lf = List.filter (fun (cpu, os) -> cpu.H.node <> kcpu || os.H.node <> kos) l
    in
    if lf <> [] then DR.HINFO lf else sentinel

  | (DR.MINFO l, DP.MINFO (krm, kem)) ->
    let lf = List.filter (fun (rm, em) -> rm.DR.owner.H.node <> krm || em.DR.owner.H.node <> kem) l
    in
    if lf <> [] then DR.MINFO lf else sentinel

  | (DR.MX l, DP.MX (kp, kn)) ->
    let lf = List.filter (fun (preference, d) -> preference <> kp || d.DR.owner.H.node <> kn) l
    in
    if lf <> [] then DR.MX lf else sentinel

  | (DR.TXT ll, DP.TXT kl) ->
    sentinel  (* TODO *)

  | (DR.RP l, DP.RP (kmbox, ktxt)) ->
    let lf = List.filter (fun (mbox, txt) -> mbox.DR.owner.H.node <> kmbox || txt.DR.owner.H.node <> ktxt) l
    in
    if lf <> [] then DR.RP lf else sentinel

  | (DR.AFSDB l, DP.AFSDB (kt, kn)) ->
    let lf = List.filter (fun (t, d) -> t <> kt || d.DR.owner.H.node <> kn) l
    in
    if lf <> [] then DR.AFSDB lf else sentinel

  | (DR.X25 l, DP.X25 k) ->
    let lf = List.filter (fun s -> s.H.node <> k) l
    in
    if lf <> [] then DR.X25 lf else sentinel

  | (DR.ISDN l, DP.ISDN (ka, ksa)) ->
    let lf = List.filter (fun (a, sa) ->
        let sa = match sa with None -> None | Some sa -> Some sa.H.node in
        a.H.node <> ka || sa <> ksa) l
    in
    if lf <> [] then DR.ISDN lf else sentinel

  | (DR.RT l, DP.RT (kp, kn)) ->
    let lf = List.filter (fun (preference, d) -> preference <> kp || d.DR.owner.H.node <> kn) l
    in
    if lf <> [] then DR.RT lf else sentinel

  | (DR.SRV l, DP.SRV (kprio, kw, kport, kn)) ->
    let lf = List.filter (fun (priority, weight, port, d) ->
        priority <> kprio || weight <> kw || port <> kport || d.DR.owner.H.node <> kn) l
    in
    if lf <> [] then DR.SRV lf else sentinel

  | (DR.DS l, DP.DS (kt, ka, kd, kn)) ->
    let lf = List.filter (fun (tag, alg, digest, k) ->
        tag <> kt || alg <> ka || digest <> kd || k.H.node <> kn) l
    in
    if lf <> [] then DR.DS lf else sentinel

  | (DR.DNSKEY l, DP.DNSKEY (kfl, ktt, kk)) ->
    let lf = List.filter (fun (fl, t, k) ->
        let tt = DP.int_to_dnssec_alg t in
        match tt with
        | None -> false
        | Some tt -> fl <> kfl || tt <> ktt || k.H.node <> kk
      ) l
    in
    if lf <> [] then DR.DNSKEY lf else sentinel

  | (DR.RRSIG l, DP.RRSIG (ktyp, kalg, klbl, kttl, kexp_ts, kinc_ts, ktag, kname, ksign)) ->
    let lf = List.filter DR.(fun {
        rrsig_type = typ;
        rrsig_alg = alg;
        rrsig_labels = lbl;
        rrsig_ttl = ttl;
        rrsig_expiry = exp_ts;
        rrsig_incept = inc_ts;
        rrsig_keytag = tag;
        rrsig_name = name;
        rrsig_sig = sign;
      } ->
        typ <> ktyp || alg <> kalg || lbl <> klbl || ttl <> kttl ||
        exp_ts <> kexp_ts || inc_ts <> kinc_ts || tag <> ktag ||
        name <> kname || sign <> ksign
      ) l
    in
    if lf <> [] then DR.RRSIG lf else sentinel

  | (DR.Unknown _, _) -> sentinel

  | _, _ -> rr

let rec filter_known_list rr knownl =
  match knownl with
  | [] -> rr
  | known::tl ->
    begin
      let frr = filter_out_known rr known.DP.rdata in
      match frr with DR.Unknown _ -> frr | _ -> filter_known_list frr tl
    end

module Make (Transport : TRANSPORT) = struct
  type timestamp = int

  type unique_key = {
    (* RFC 6762 section 10.2: uniqueness is based on name/rrtype/rrclass *)
    name : Dns.Name.domain_name;
    rrtype : DP.rr_type;
    (* The only rrclass we support is RR_IN *)
  }

  type unique_state = {
    rdata : DP.rdata;
    mutable probing : bool;
    mutable response_seen_time : timestamp;
    mutable confirmed : bool;
  }

  type unique_assoc = unique_key * unique_state

  type t = {
    db : Dns.Loader.db;
    dnstrie : Dns.Trie.dnstrie;
    mutable unique : unique_assoc list;
  }

  let of_zonebufs zonebufs =
    let db = List.fold_left (fun db -> Dns.Zone.load ~db []) 
        (Dns.Loader.new_db ()) zonebufs in
    let dnstrie = db.Dns.Loader.trie in
    { db; dnstrie; unique=[] }

  let of_zonebuf zonebuf = of_zonebufs [zonebuf]

  let add_unique_hostname t name_str ip =
    (* TODO: support IPv6 with AAAA *)
    let name = Dns.Name.string_to_domain_name name_str in
    (* Add it to the trie *)
    Dns.Loader.add_a_rr ip 120l name t.db;
    (* Add an entry to our own list of unique records *)
    let key = {name; rrtype=DP.RR_A} in
    let value = {
      rdata=DP.A ip;
      probing=false; response_seen_time=0; confirmed=false
    } in
    t.unique <- (key, value) :: t.unique

  let unique_of_key t name rrtype =
    try
      let unique = List.assoc {name; rrtype} t.unique in
      Some unique
    with
    | Not_found -> None

  let unique_of_rrset t name rrset =
    match rrset with
    | DR.A l -> unique_of_key t name DP.RR_A
    | _ -> None  (* TODO *)

  (* This predicate controls the cache-flush bit *)
  let is_confirmed_unique t owner rdata =
    (* FIXME: O(N) *)
    match unique_of_key t owner (DP.rdata_to_rr_type rdata) with
    | Some unique -> unique.confirmed
    | None -> false

  let prepare_probe t =
    let questions = ref [] in
    let authorities = ref [] in
    let probe_node node =
      let probe_rrset rrset =
        match unique_of_rrset t node.DR.owner.H.node rrset.DR.rdata with
        | Some unique ->
          if unique.confirmed then
            false  (* Only probe if not already confirmed *)
          else
            begin
              unique.probing <- true;
              (* RFC 6762 section 8.2 - populate the Authority section *)
              let auth = DP.({name=node.DR.owner.H.node; cls=DP.RR_IN; flush=true; ttl=120l; rdata=unique.rdata}) in
              authorities := auth :: !authorities;
              true
            end
        | None -> false
      in
      (* The probe question specifies Q_ANY_TYP, so we send it if any of the RRs are unique *)
      let any = List.fold_left (fun any rrset -> probe_rrset rrset || any) false node.DR.rrsets in
      if any then
        let q = DP.({
            q_name = node.DR.owner.H.node;
            q_type = Q_ANY_TYP;
            q_class = Q_IN;
            q_unicast = QU;  (* request unicast response as per RFC 6762 section 8.1 para 6 *)
          }) in
        questions := q :: !questions
    in
    Dns.Trie.iter probe_node t.dnstrie;
    if !questions = [] then
      (* There are no unique records to probe for *)
      None
    else
      let detail = DP.({ qr=Query; opcode=Standard; aa=false; tc=false; rd=false; ra=false; rcode=NoError}) in
      let query = DP.({ id=0; detail; questions= !questions; answers=[]; authorities= !authorities; additionals=[]; }) in
      let obuf = DP.marshal (Transport.alloc ()) query in
      Some obuf

  let probe t =
    (* TODO: probes should be per-link if there are multiple NICs *)
    MProf.Trace.label "probe";
    match prepare_probe t with
    | None -> return ()
    | Some probe ->
      (* Random delay of 0-250 ms *)
      Transport.sleep (Random.float 0.25) >>= fun () ->
      (* First probe *)
      let dest = (multicast_ip,5353) in
      Transport.write dest probe >>= fun () ->
      (* Fixed delay of 250 ms *)
      Transport.sleep 0.25 >>= fun () ->
      (* Second probe *)
      Transport.write dest probe >>= fun () ->
      (* Fixed delay of 250 ms *)
      Transport.sleep 0.25 >>= fun () ->
      (* Third probe *)
      Transport.write dest probe >>= fun () ->
      (* Fixed delay of 250 ms *)
      Transport.sleep 0.25 >>= fun () ->
      (* Now confirmed unique *)
      List.iter (fun (key,unique) ->
          if unique.probing then begin
            unique.probing <- false;
            unique.confirmed <- true
          end
        ) t.unique;
      return ()

  let announce t ~repeat =
    MProf.Trace.label "announce";
    let questions = ref [] in
    let build_questions node =
      let q = DP.({
        q_name = node.DR.owner.H.node;
        q_type = Q_ANY_TYP;
        q_class = Q_IN;
        q_unicast = QM;
      }) in
      questions := q :: !questions
    in
    let dedup_answer answer =
      (* Delete duplicate RRs from the response *)
      (* FIXME: O(N*N) *)
      (* TODO: Dns.Query shouldn't generate duplicate RRs *)
      let rr_eq rr1 rr2 =
        rr1.DP.name = rr2.DP.name &&
        DP.compare_rdata rr1.DP.rdata rr2.DP.rdata = 0
      in
      let rec dedup l =
        match l with
        | [] -> l
        | hd::tl -> if List.exists (rr_eq hd) tl
          then tl
          else hd :: dedup tl
      in
      { answer with DQ.answer = dedup answer.DQ.answer; DQ.additional = [] }
    in
    let rec write_repeat dest obuf repeat sleept =
      (* RFC 6762 section 11 - TODO: send with IP TTL = 255 *)
      Transport.write dest obuf >>= fun () ->
      if repeat = 1 then
        return ()
      else
        Transport.sleep sleept >>= fun () ->
        write_repeat dest obuf (repeat - 1) (sleept *. 2.0)
    in
    Dns.Trie.iter build_questions t.dnstrie;
    let answer = DQ.answer_multiple ~dnssec:false ~mdns:true ~flush:(is_confirmed_unique t) !questions t.dnstrie in
    let answer = dedup_answer answer in
    let dest_host = multicast_ip in
    let dest_port = 5353 in
    (* TODO: refactor Dns.Query to avoid the need for this fake query *)
    let fake_detail = DP.({ qr=Query; opcode=Standard; aa=false; tc=false; rd=false; ra=false; rcode=NoError}) in
    let fake_query = DP.({
        id=0;
        detail=fake_detail;
        questions= !questions; answers=[]; authorities=[]; additionals=[];
    }) in
    let response = DQ.response_of_answer ~mdns:true fake_query answer in
    if response.DP.answers = [] then
      return ()
    else
      (* TODO: limit the response packet size *)
      let obuf = Transport.alloc () in
      match DS.marshal obuf fake_query response with
      | None -> return ()
      | Some obuf -> write_repeat (dest_host,dest_port) obuf repeat 1.0

  let get_answer t dp =
    let filter name rrset =
      (* RFC 6762 section 7.1 - Known Answer Suppression *)
      (* First match on owner name and check TTL *)
      let relevant_known = List.filter (fun known ->
          (name = known.DP.name) && (known.DP.ttl >= Int32.div rrset.DR.ttl 2l)
        ) dp.DP.answers
      in
      (* Now suppress known records based on RR type *)
      let rdata = filter_known_list rrset.DR.rdata relevant_known in
      {
        DR.ttl = (match rdata with DR.Unknown _ -> 0l | _ -> rrset.DR.ttl);
        DR.rdata = rdata;
      }
    in
    (* DNSSEC disabled for testing *)
    DQ.answer_multiple ~dnssec:false ~mdns:true ~filter ~flush:(is_confirmed_unique t) dp.DP.questions t.dnstrie

  let process_query t src dst dp =
    let get_delay legacy response =
      if legacy then
        (* Zero delay for legacy mode *)
        return ()
      else if List.exists (fun a -> a.DP.flush) response.DP.answers then
        (* Zero delay for records that have been verified as unique *)
        (* TODO: send separate unique and non-unique responses if applicable *)
        return ()
      else
        (* Delay response for 20-120 ms *)
        Transport.sleep (0.02 +. Random.float 0.1)
    in
    match Dns.Protocol.contain_exc "answer" (fun () -> get_answer t dp) with
    | None -> return ()
    | Some answer when answer.DQ.answer = [] -> return ()
    | Some answer ->
      let src_host, src_port = src in
      let legacy = (src_port != 5353) in
      let reply_host = if legacy then src_host else multicast_ip in
      let reply_port = src_port in
      (* RFC 6762 section 18.5 - TODO: check tc bit *)
      MProf.Trace.label "post delay";
      (* NOTE: echoing of questions is still required for legacy mode *)
      let response = DQ.response_of_answer ~mdns:(not legacy) dp answer in
      if response.DP.answers = [] then
        return ()
      else
        begin
          (* Possible delay before responding *)
          get_delay legacy response >>= fun () ->
          (* TODO: limit the response packet size *)
          let obuf = Transport.alloc () in
          match DS.marshal obuf dp response with
          | None -> return ()
          | Some obuf ->
            (* RFC 6762 section 11 - TODO: send with IP TTL = 255 *)
            Transport.write (reply_host,reply_port) obuf
        end

  let process_response t dp =
    (* Check for conflicts with our unique records *)
    (* TODO: process responses *)
    (* RFC 6762 section 10.5 - TODO: passive observation of failures *)
    printf "Response ignored.\n%!";
    return ()

  let process t ~src ~dst ibuf =
    MProf.Trace.label "mDNS process";
    let open DP in
    match DS.parse ibuf with
    | None -> return ()
    | Some dp when dp.detail.opcode != Standard ->
      (* RFC 6762 section 18.3 *)
      return ()
    | Some dp when dp.detail.rcode != NoError ->
      (* RFC 6762 section 18.11 *)
      return ()
    | Some dp when dp.detail.qr = Query -> process_query t src dst dp
    | Some dp -> process_response t dp

  let trie t = t.dnstrie

end
