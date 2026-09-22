let test_version () =
  Alcotest.(check string) "version" "0.1.0" Contract_lab.Version.version

let () =
  Alcotest.run "contract-lab"
    [ ("smoke", [ Alcotest.test_case "version" `Quick test_version ]) ]
