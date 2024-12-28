// Usage `jai .\tests.jai`
// Runs the examples sequentially and checks if they compile and run successfully.

#run {
    test("./examples", "first");
    test("./examples", "file_examples");

    set_build_options_dc(.{do_output=false});
}

test :: (dir: string, filestem: string){
    print("Test: % ", filestem);
    process_result, output_string, error_string := Process.run_command("jai", tprint("%.jai", filestem), working_directory=dir, capture_and_return_output=true);
    if process_result.type != .EXITED {
        log_error("Could not compile test: %", filestem);
        return;
    }
    if process_result.exit_code != 0 {
        log("\nSTDOUT:%", output_string);
        log_error("STDERR:%", error_string);
        log_error("Test failed compilation: %", filestem);
        return;
    } else {
        print("-> Compiled ");
    }

    process_result, output_string, error_string = Process.run_command(tprint("%/%", dir, filestem), working_directory=dir, capture_and_return_output=true);
    if process_result.type != .EXITED {
        log_error("Could not run test: %", filestem);
        return;
    }
    if process_result.exit_code != 0 {
        log("\nSTDOUT:%", output_string);
        log_error("STDERR:%", error_string);
        log_error("Test failed running: %", filestem);
        return;
    } else {
        print("-> Passed\n");
    }
}


Process :: #import "Process";
#import "Basic";
#import "Compiler";
