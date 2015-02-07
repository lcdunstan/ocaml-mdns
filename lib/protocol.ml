(*
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

open Dns

module Client : Dns.Protocol.CLIENT = struct
  type context = Packet.t

  let get_id () = 0

  let marshal ?alloc q =
    [q, Packet.marshal (Buf.create ?alloc 4096) q]

  let packet_matches query packet =
    let open Packet in
    let rr_answers_question q rr =
      q.q_name = rr.name &&
      q_type_matches_rr_type q.q_type (rdata_to_rr_type rr.rdata) &&
      q.q_class = Q_IN && rr.cls = RR_IN
    in
    let rec rrlist_answers_question q rrlist =
      match rrlist with
      | [] -> false
      | rr :: tl -> rr_answers_question q rr || rrlist_answers_question q tl
    in
    let rec rrlist_answers_questions qs rrlist =
      match qs with
      | [] -> false
      | q :: tl -> rrlist_answers_question q rrlist || rrlist_answers_questions tl rrlist
    in
    packet.detail.qr = Response &&
      packet.detail.opcode = Standard &&
      packet.detail.rcode = NoError &&
      rrlist_answers_questions query.questions packet.answers

  let parse q buf =
    let pkt = Packet.parse buf in
    if packet_matches q pkt then Some pkt else None

  let timeout _id = Dns.Protocol.Dns_resolve_timeout
end

let contain_exc l v =
  try
    Some (v ())
  with exn ->
    Printexc.print_backtrace stderr;
    Printf.eprintf "mdns %s exn: %s\n%!" l (Printexc.to_string exn);
    None

module Server : Dns.Protocol.SERVER with type context = Packet.t = struct
  type context = Packet.t

  let query_of_context x = x

  let parse buf = contain_exc "parse" (fun () -> Packet.parse buf)
  let marshal buf _q response =
    contain_exc "marshal" (fun () -> Packet.marshal buf response)
end
