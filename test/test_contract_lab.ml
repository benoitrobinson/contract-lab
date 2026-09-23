let test_version () =
  Alcotest.(check string) "version" "0.1.0" Contract_lab.Version.version

let () =
  Alcotest.run "contract-lab"
    [
      ("smoke", [ Alcotest.test_case "version" `Quick test_version ]);
      ("american", Test_american.suite);
      ("barrier", Test_barrier.suite);
      ("simplify", Test_simplify.suite);
      ("study", Test_study.suite);
      ("lsm", Test_lsm.suite);
    ]
