# hjson-d

Hjson-d is a [HJSON](hjson.org) parser written in D.
HJSON is a syntax extension to JSON which improves readability and helps avoid bugs caused by missing/trailing commas:
```hjson
// example.hjson
{
    "name": "HJSON",
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

### Usage
You can parse HJSON into a `std.json.JSONValue` by importing `hjson` and using `parseHJSON`:
```d
import std.file : readText;
import hjson;

JSONValue value = readText("example.hjson").parseHJSON;
```
When `parseHJSON` encounters invalid HJSON it will throw a `HJSONException`.

### Limitations
- Emitting HJSON is not supported
- `parseHJSON` only reads a single HJSON value and will not attempt to look further in the input to find errors. Because of that certain errors will not be detected: 
```hjson
[1, 2, 3, 4] 5 #Trailing 5 will not cause an error because parsing stops after [1, 2, 3, 4]
```
- Parsing from arbitrary forward ranges is currently not supported, but is planned for the future.