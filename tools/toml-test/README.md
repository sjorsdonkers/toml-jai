[toml-test](https://github.com/toml-lang/toml-test) is a language-agnostic test suite to verify the correctness of TOML parsers and writers.

A decoder and encoder has been implemented for use with `toml-test`. The decoder accepts a Toml on stdin and returns a toml-test Json on stdout. The encoder accepts a toml-test Json on stdin and returns a Toml on stdout.  
Currently some `invalid` cases are not passing yet as `toml-jai` does not have a strict mode yet.

## Run

> The `toml-test` executable should be in the PATH or placed in this directory.

Test with the decoder:
```sh
jai ./decoder.jai
./toml-test ./decoder -run 'valid/*'
```

Test with the encoder:
```sh
jai ./encoder.jai
./toml-test -encoder ./encoder
```

The `run_toml-tests` app is used for the test framework to compile and run both in sequence.
