use Test::More 0.94;
eval { use Test::CheckDeps 0.007; 1 }
    or plan skip_all => "Test::CheckDeps 0.007 required";

check_dependencies();

done_testing();

