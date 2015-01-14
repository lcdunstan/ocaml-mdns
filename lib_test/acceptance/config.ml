open Mirage

(* Built from the tmp subdirectory *)
let data = crunch "../../mirage/data"

let my_ipv4_conf =
  let i = Ipaddr.V4.of_string_exn in
  {
    address  = i "192.168.3.3";
    netmask  = i "255.255.255.0";
    gateways = [];
  }

let stack =
  direct_stackv4_with_static_ipv4 default_console tap0 my_ipv4_conf

let main =
  foreign "Unikernel.Main" (console @-> kv_ro @-> stackv4 @-> job)

let () =
  add_to_ocamlfind_libraries [ "mdns.lwt-core"; ];
  register "mirage-guest" [ main $ default_console $ data $ stack ]

