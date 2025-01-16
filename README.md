# Luajit Obfuscator

I don't like writing obfuscators as they always have issues and don't work correctly and become hard to maintain over time. This is just a simple obfuscator by turning lua code into luajit bytecode then back to lua code.

Output can be really big, especially if you run it more than one time on the output you get from the previous run.

It is not perfect but can waste some time for someone who wants to read your code.

## Usage

`obfuscate`(`.exe`) needs `obfuscator.lua`/`obfuscator-src/obfuscator.lua` to run, you feed it input using stdin and it will output the obfuscated code to stdout.

You can pass `-n` where `n` is the number of times you want to run the obfuscator on the output. Please don't try to go over 2 as output is already huge just for couple of lines of code. Eg. "-2" will run the obfuscator twice on the output.

A simple `print(true)` with obfuscation level set to 2 will output around 14k characters.

## Credits

- Thanks to [meepen](https://github.com/meepen) for his [LuaJIT VM](https://gist.github.com/meepen/807dd81a572ffb0f28a8c44c04922fdd) I used it as a reference.
- Thanks to [tarantool team for their LuaJIT Bytecodes reference](https://github.com/tarantool/tarantool/wiki/LuaJIT-Bytecodes) that they restored from LuaJIT 2.0.5.

## Note

Please don't use this for malicious purposes, this is made for people who want to protect their addons from being stolen.

## Contributing

If you find this project useful, please consider contributing rather than just forking it and making it private. Whether it's fixing a bug, adding a feature, or improving documentation, your contributions help improve the project for everyone.

Don't just take it—help make it better!
