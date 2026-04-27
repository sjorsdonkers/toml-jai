[toml-test](https://github.com/toml-lang/toml-test) is a language-agnostic test suite to verify the correctness of TOML parsers and writers.

A decoder and encoder has been implemented for use with `toml-test`. The decoder accepts a Toml on stdin and returns a toml-test Json on stdout. The encoder accepts a toml-test Json on stdin and returns a Toml on stdout.
A perf app is implemented to run the performance test from `toml-test`.

## Run

> The `jai` and `toml-test-v2.1.0` executables should be in the PATH.

Test with the decoder and encoder:
```sh
jai ./decoder.jai
jai ./encoder.jai
toml-test-v2.1.0 test -decoder="./decoder --toml=1.0" -encoder="./encoder --toml=1.0" -toml="1.0"
```

The `run_toml-tests` app is used for the test framework to compile and run both in sequence.

Run perf: (note: test files were generated with v1.6.0)
```sh
toml-test-v1.6.0 -cat 10 > 10kb.toml
jai ./perf.jai
./perf 10kb.toml
```
