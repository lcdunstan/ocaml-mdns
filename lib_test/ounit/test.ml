
open OUnit2

let () =
  run_test_tt_main ("mdns" >::: [
      Test_mdns_server.tests;
    ])

