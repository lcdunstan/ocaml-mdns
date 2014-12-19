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

type process = src:ip_endpoint -> dst:ip_endpoint -> Dns.Buf.t -> unit Lwt.t

type unique = Unique | Shared

type commfn = {
  allocfn : unit -> Dns.Buf.t;
  txfn    : ip_endpoint -> Dns.Buf.t -> unit Lwt.t;
  sleepfn : float -> unit Lwt.t;
}

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

let process_of_zonebufs zonebufs commfn =
  let db = List.fold_left (fun db -> Dns.Zone.load ~db []) 
    (Dns.Loader.new_db ()) zonebufs in
  let dnstrie = db.Dns.Loader.trie in
  let get_answer dp =
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
    DQ.answer_multiple ~dnssec:false ~mdns:true ~filter dp.DP.questions dnstrie
  in
  let callback ~src ~dst ibuf =
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
    | Some dp when dp.detail.qr = Query ->
      begin
        match Dns.Protocol.contain_exc "answer" (fun () -> get_answer dp) with
        | None -> return ()
        | Some answer when answer.DQ.answer = [] -> return ()
        | Some answer ->
          let src_host, src_port = src in
          let legacy = (src_port != 5353) in
          let dest_host = if legacy then src_host else multicast_ip in
          (* RFC 6762 section 18.5 - TODO: check tc bit *)
          (* TODO: zero delay for records that have been verified as unique *)
          (* Delay response for 20-120 ms *)
          let delay = if legacy then 0.0 else 0.02 +. Random.float 0.1 in
          commfn.sleepfn delay >>= fun () ->
          MProf.Trace.label "post delay";
          (* NOTE: echoing of questions is still required for legacy mode *)
          let response = DQ.response_of_answer ~mdns:(not legacy) dp answer in
          if response.answers = [] then
            return ()
          else
            let obuf = commfn.allocfn () in
            match DS.marshal obuf dp response with
            | None -> return ()
            | Some obuf ->
              (* RFC 6762 section 11 - TODO: send with IP TTL = 255 *)
              commfn.txfn (dest_host,src_port) obuf
      end

    | Some dp ->
      (* TODO: process responses *)
      (* RFC 6762 section 10.5 - TODO: passive observation of failures *)
      printf "Response ignored.\n%!";
      return ()
  in
  callback


let process_of_zonebuf zonebuf commfn =
  process_of_zonebufs [zonebuf] commfn

