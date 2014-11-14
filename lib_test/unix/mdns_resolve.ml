(*
 * Copyright (c) 2014 Luke Dunstan <LukeDunstan81@gmail.com>
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

let main =
  let dest_ip = Ipaddr.of_string_exn "224.0.0.251" in
  let dest_port = 5353 in
  let config = `Static ([(dest_ip, dest_port)], []) in
  let q_class = Dns.Packet.Q_IN in
  let q_type = Dns.Packet.Q_A in
  let q_name = Dns.Name.string_to_domain_name "cubieboard2.local" in
  try_lwt
    Printf.printf "create...\n%!";
    Dns_resolver_unix.create ~config () >>= fun resolver ->
    Printf.printf "resolve...\n%!";
    Dns_resolver_unix.resolve resolver q_class q_type q_name >>= fun result ->
    Printf.printf "to_string...\n%!";
    Printf.printf "Result: %s\n%!" (Dns.Packet.to_string result);
    return ()
  with
  | _ -> Printf.printf "Exception: %s\n%!" (Printexc.get_backtrace()); return ()

let _ =
  Lwt_main.run main

