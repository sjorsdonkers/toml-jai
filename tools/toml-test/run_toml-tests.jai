// Compiles the toml-test decoder and encoder
#run {
    args:= join(..array_view(get_toplevel_command_line(), 2), separator=" ");

    result, stdout, stderr := run_command("jai", "decoder.jai", args, capture_and_return_output=true);
    log("\n%", stdout);
    if stderr log_error("STDERR:\n%", stderr);
    if result.type != .EXITED || result.exit_code != 0 exit(1);

    result, stdout, stderr = run_command("jai", "encoder.jai", args, capture_and_return_output=true);
    log("\n%", stdout);
    if stderr log_error("STDERR:\n%", stderr);
    if result.type != .EXITED || result.exit_code != 0 exit(1);
}

// Runs the toml-test with the decoder and encoder (for the set of test that are successful)
// the `toml-test` executable is expected to be in the current directory or in the PATH
main :: () {
    #if OS == {
        case .WINDOWS; bin := "toml-test-v2.1.0.exe";
        case;          bin := "toml-test-v2.1.0";
    }
    // Check if the toml-test can be found
    result := run_command(bin, "version", capture_and_return_output=true);
    if result.type != .EXITED || result.exit_code != 0 {
        log_error("'%s' not found in PATH, or not execute permission, see https://github.com/toml-lang/toml-test", bin);
        exit(2);
    }

    result=, stdout, stderr := run_command(bin, "test", "-decoder=./decoder", "-encoder=./encoder", "-toml=1.0", capture_and_return_output=true);
    log("\n%", stdout);
    if stderr log_error(stderr);
    if result.type != .EXITED || result.exit_code != 0 exit(1);
}

#import "Process";
#import "Basic";
#import "String";
#import "Compiler";
