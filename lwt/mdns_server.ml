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

type ip_endpoint = Ipaddr.V4.t * int

type process = src:ip_endpoint -> dst:ip_endpoint -> Dns.Buf.t -> unit Lwt.t

type unique = Unique | Shared

type commfn = {
  allocfn : unit -> Dns.Buf.t;
  txfn    : ip_endpoint -> Dns.Buf.t -> unit Lwt.t;
  sleepfn : float -> unit Lwt.t;
}

let multicast_ip = Ipaddr.V4.of_string_exn "224.0.0.251"

let process_of_zonebufs zonebufs commfn =
  let db = List.fold_left (fun db -> Dns.Zone.load ~db []) 
    (Dns.Loader.new_db ()) zonebufs in
  let dnstrie = db.Dns.Loader.trie in
  let get_answer questions =
    (* DNSSEC disabled for testing *)
    DQ.answer_multiple ~dnssec:false ~mdns:true questions dnstrie
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
        match Dns.Protocol.contain_exc "answer" (fun () -> get_answer dp.questions) with
        | None -> return ()
        | Some answer ->
          let src_host, src_port = src in
          let legacy = (src_port != 5353) in
          let dest_host = if legacy then src_host else multicast_ip in
          (* RFC 6762 section 18.5 - TODO: check tc bit *)
          (* RFC 6762 section 7.1 - TODO: Known Answer Suppression *)
          (* TODO: zero delay for records that have been verified as unique *)
          (* Delay response for 20-120 ms *)
          let delay = if legacy then 0.0 else 0.02 +. Random.float 0.1 in
          commfn.sleepfn delay >>= fun () ->
          MProf.Trace.label "post delay";
          (* NOTE: echoing of questions is still required for legacy mode *)
          let response = DQ.response_of_answer ~mdns:(not legacy) dp answer in
          if response.answers = [] then
            begin
              printf "No answers\n%!";
              return ()
            end
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

