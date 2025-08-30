[toml-test](https://github.com/toml-lang/toml-test) is a language-agnostic test suite to verify the correctness of TOML parsers and writers.

A decoder and encoder has been implemented for use with `toml-test`. The decoder accepts a Toml on stdin and returns a toml-test Json on stdout. The encoder accepts a toml-test Json on stdin and returns a Toml on stdout.
A perf app is implemented to run the performance test from `toml-test`.

## Run

> The `jai` and `toml-test` executables should be in the PATH.

Test with the decoder:
```sh
jai ./decoder.jai
toml-test ./decoder -run 'valid/*'
```

Test with the encoder:
```sh
jai ./encoder.jai
toml-test -encoder ./encoder
```

The `run_toml-tests` app is used for the test framework to compile and run both in sequence.

Run perf:
```sh
toml-test -cat 10 > 10kb.toml
jai ./perf.jai
./perf 10kb.toml
```
