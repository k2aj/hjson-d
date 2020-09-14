# hjson-d

Hjson-d is a [Hjson](https://hjson.github.io/) parser written in D.
Hjson is a syntax extension to JSON, designed to be easier for humans to work with. It improves readability and helps avoid bugs caused by missing/trailing commas:
```hjson
// example.hjson
{
    "name": "Hjson",
    "readable": {
        omitQuotes: This is a quoteless string
        omitCommas: [
            1
            2
            3
        ]
        trailingCommas: {
            a : true,
            b : false,
            c : null,
        }
        multilineStrings:
            '''
            Lorem
            ipsum
            '''
        # Comments
        // C-style comments
        /*
            Block
            comments
        */
    }
}
```

## Getting started
Add hjson-d to your DUB project:
```
dub add hjson-d
```

## Features

### Simple parsing
Hjson strings can be parsed using the `parseHjson` method:
```d
import std.json : JSONValue;
import std.file : readText;
import hjson;

JSONValue value = readText("example.hjson").parseHjson;
```
When `parseHjson` encounters invalid input, it will throw a `HjsonException` describing the error.

### [ASDF](https://code.dlang.org/packages/asdf) interop
Add `hjson-d:asdf` to your DUB project to allow parsing Hjson directly into ASDF representation:
```
dub add hjson:asdf
```
All you have to do is call `parseHjsonToAsdf`:
```d
import asdf.asdf : Asdf;
import std.file : readText;
import hjson.asdf;

Asdf asdf = readText("example.hjson").parseHjsonToAsdf;
```

## Limitations
- Emitting Hjson is not supported.
- `parseHjson` only reads a single Hjson value and will not attempt to look further in the input to find errors. Because of that certain errors will not be detected: 
```hjson
[1, 2, 3, 4] 5 #Trailing 5 will not cause an error because parsing stops after [1, 2, 3, 4]
```
- Parsing from arbitrary forward ranges is currently not supported, but is planned for the future.

## Bugs
- Omitting braces for root object is not supported.
