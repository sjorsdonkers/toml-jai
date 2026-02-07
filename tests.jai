// Usage `jai .\tests.jai`
// Runs the examples sequentially and checks if they compile and run successfully.

#run {
    args:= join(..array_view(get_toplevel_command_line(), 2), separator=" ");
    if args print("Running tests with args: %\n", args);

    t0 := seconds_since_init();
    test("./examples",        "first",              args);
    test("./examples",        "union_and_overlay",  args);
    test("./examples",        "file_examples",      args);
    test("./examples",        "validation",         args);
    test("./examples",        "custom_handlers",    args);
    test("./examples",        "formatting_control", args);
    test("./tools/toml-test", "run_toml-tests",     args);
    print("Tests ran in % seconds\n", seconds_since_init() - t0);

    set_build_options_dc(.{do_output=false});
}

test :: (dir: string, filestem: string, args: string){
    print("Test: %", filestem); for 0..17-filestem.count write_string(" ");
    t1 := seconds_since_init();
    process_result, output_string, error_string := Process.run_command("jai", tprint("%.jai", filestem), args, working_directory=dir, capture_and_return_output=true);
    if process_result.type != .EXITED {
        log_error("Could not compile test: %", filestem);
        return;
    }
    if process_result.exit_code != 0 {
        log("\nSTDOUT:\n%", output_string);
        log_error("STDERR:\n%", error_string);
        log_error("Test failed compilation: %", filestem);
        return;
    } else {
        print(" -> Compiled (%s)", FormatFloat.{value=seconds_since_init() - t1, trailing_width=3, zero_removal=.NO});
    }

    t2 := seconds_since_init();
    filepath := #ifx OS == .WINDOWS tprint("%/%", dir, filestem) else tprint("./%", filestem);
    process_result, output_string, error_string = Process.run_command(filepath, working_directory=dir, capture_and_return_output=true);
    if process_result.type != .EXITED {
        log_error("Could not run test: %/%", dir,filestem);
        return;
    }
    if process_result.exit_code == {
    case 0; print(" -> Passed (%s)\n", FormatFloat.{value=seconds_since_init() - t2, trailing_width=3, zero_removal=.NO});
    case 2; print(" -> Skipped\n");
    case;
        log("\nSTDOUT:\n%", output_string);
        log_error("STDERR:\n%", error_string);
        log_error("Test failed running: %/%", dir, filestem);
        return;
    }
}


Process :: #import "Process";
#import "Basic";
#import "String";
#import "Compiler";
