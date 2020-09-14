module hjson.parser;

public import std.json : JSONValue;
import std.typecons : Flag;
import std.array;
import std.range;
import std.algorithm;
import std.uni;
import std.ascii : isDecimalDigit = isDigit, isHexDigit;
import std.conv : to, ConvException;
import std.exception : basicExceptionCtors, _enforce = enforce;
import std.format : format;

import hjson.adapter;

/** Parses a HJSON value into a `JSONValue` object.
    Params:
        hjson = string containing the HJSON.
    Throws:
        `HJSONException` when passed invalid HJSON.
    Returns:
        Parsed JSONValue.
*/
JSONValue parseHJSON(string hjson)
{
    JSONValue result;
    scope consumer = StdJsonSerializer(&result);
    hjson.parseHJSON(consumer);
    return result;
}

void parseHJSON(Consumer)(string hjson, ref Consumer consumer)
{
    size_t collumn = 0;
    hjson.parseValue(collumn,consumer);
}

///
class HJSONException : Exception
{
    mixin basicExceptionCtors;
}

/** Parses a single HJSON value (object, array, string, number, bool or null).
    Params:
        hjson = string being parsed. May contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                HJSON value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                  last line feed. Will be updated by the function. 
                  Needed to properly parse multiline strings.
        consumer = Constructs the result
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
*/
void parseValue(Consumer)(ref string hjson, ref size_t collumn, ref Consumer consumer)
{
    hjson.skipWC(collumn);
    enforce(!hjson.empty, "Expected a value before EOF.");
    
    if(hjson.front == '{')
    {
        auto state = consumer.objectBegin();
        hjson.parseAggregate!('{', '}', parseObjectMember)(collumn, consumer);
        consumer.objectEnd(state);
    }
    else if(hjson.front == '[')
    {
        auto state = consumer.arrayBegin();
        hjson.parseAggregate!('[', ']', (ref hjs, ref col, ref ser){
            ser.elemBegin;
            hjs.parseValue(col,ser);
        })(collumn,consumer);
        consumer.arrayEnd(state);
    }
    else if(hjson.save.startsWith("true"))
    {
        if(!hjson.tryParseBuiltin(collumn,true,"true",consumer))
            consumer.putValue(hjson.parseQuotelessString());
    }
    else if(hjson.save.startsWith("false"))
    {
        if(!hjson.tryParseBuiltin(collumn,false,"false",consumer))
            consumer.putValue(hjson.parseQuotelessString());
    }
    else if(hjson.save.startsWith("null"))
    {
        if(!hjson.tryParseBuiltin(collumn,null,"null",consumer))
            consumer.putValue(hjson.parseQuotelessString());
    }
    else if(hjson.front == '"')
        consumer.putValue(hjson.parseJSONString(collumn));
    else if(hjson.front == '\'')
    {
        auto r = hjson.save;
        if(r.startsWith("'''"))
            consumer.putValue(hjson.parseMultilineString(collumn));
        else
            consumer.putValue(hjson.parseJSONString(collumn));
    }
    else if(!hjson.front.isPunctuator)
    {
        if(!hjson.tryParseNumber(consumer))
            consumer.putValue(hjson.parseQuotelessString());
    }
    else throw new HJSONException("Invalid HJSON.");
}

/** Parses a single HJSON object or array.
    Params:
        hjson = string being parsed. Must not contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                HJSON value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                  last line feed. Will be updated by the function. 
                  Needed to properly parse multiline strings.
        aggregate = JSONValue object or array into which the result will be
                    stored. Must be initialised by the caller.
        start = Token which marks the beginning of parsed aggregate ('[' for array, '{' for object)
        end = Token which marks the end of parsed aggregate (']' for array, '}' for object)
        parseMember = Function used to parse a single aggregate member. Parameters are
                      the same as `parseAggregate`. HJSON passed to `parseMember` contains
                      no leading whitespace.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
*/
void parseAggregate
    (dchar start, dchar end, alias parseMember, Consumer)
    (ref string hjson, ref size_t collumn, ref Consumer consumer)
in(!hjson.empty)
in(hjson.front == start)
{
    // Get rid of opening '{' and whitespace
    hjson.popFront();
    ++collumn;
    hjson.skipWC(collumn);

    //Handle empty HJSON object {whitespace/comments only}
    enforce(!hjson.empty, "Expected member or '%s' before EOF.".format(end));
    if(hjson.front == end)
    {
        hjson.popFront();
        ++collumn;
        return;
    }

    //Now we know we have at least one member
    parseMember(hjson, collumn, consumer);

    while(true)
    {
        // Skip member separator
        bool gotMemberSeparator = hjson.skipWC(collumn);
        enforce(!hjson.empty);
        if(hjson.front == ',')
        {
            hjson.popFront();
            ++collumn;
            gotMemberSeparator = true;
            hjson.skipWC(collumn);
            enforce(!hjson.empty);
        }

        if(hjson.front == end)
        {
            hjson.popFront();
            ++collumn;
            return;
        }
        else
        {
            enforce(gotMemberSeparator, hjson);
            parseMember(hjson, collumn, consumer);
        }
    }
    assert(0, "Shouldn't get there");
}

/** In JSON you can determine the type of the parsed value by looking at just their
    first character. In HJSON if you follow a valid JSON number/bool/null with certain other
    characters it will turn into a quoteless string. This function checks whether parsed
    value turns into a quoteless string by looking at the following characters.

    Params:
        sufix = HJSON following the previously parsed value.
    Returns: Whether `sufix` turns the preceding HJSON number/bool/null into a quoteless string.
*/
bool turnsIntoQuotelessString(string sufix)
{
    if(
        !sufix.empty &&
        sufix.front != ',' &&
        sufix.front != ']' &&
        sufix.front != '}' &&
        sufix.front != '\n'
    ) {
        // If there is a comment-starting token NOT SEPARATED BY WHITESPACE
        // then we treat the entire thing as quoteless string
        // 1234#notcomment is a quoteless string
        // 1234 #comment is a number and a comment
        foreach(commentStart; ["//", "/*", "#"])
            if(sufix.save.startsWith(commentStart))
                return true;
        
        if(sufix.front.isWhite)
        {
            // We have whitespace after the number, but there is a non-punctuator token before
            // the end of the line, so it's a quoteless string
            size_t dummyCollumn;
            if(
                !skipWC(sufix, dummyCollumn) && 
                !sufix.empty && 
                sufix.front != ',' &&
                sufix.front != ']' &&
                sufix.front != '}'
            ) return true;
        }
        else return true; //number followed by non-whitespace, non-comma char -> quoteless string
    }
    return false;
}

/** Attempts to parse a builtin constant.
    Params:
        hjson = string being parsed. Must not contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                HJSON value is consumed if and only if the constant was
                succesfully parsed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                  last line feed. Will be updated by the function. 
                  Needed to properly parse multiline strings.
        value = Value of the constant.
        repr = How the constant is represented in HJSON.
        consumer = Used to return the parsed value.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
    Returns: 
    `true` if parsing the constant succeeds, `false` if the value was actually a quoteless string.
*/
bool tryParseBuiltin(T,Consumer)(ref string hjson, ref size_t collumn, T value, string repr, ref Consumer consumer)
{
    auto sufix = hjson[repr.length..$];
    if(turnsIntoQuotelessString(sufix)) return false;
    else 
    {
        consumer.putValue(value);
        hjson = sufix;
        collumn += repr.walkLength;
        return true;
    }
}

/** Attempts to parse a HJSON number.
    Params:
        hjson = string being parsed. Must not contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                HJSON value is consumed if and only if the number was
                succesfully parsed.
        consumer = Used to return the parsed value.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
    Returns: 
    `true` if parsing the number succeeds, `false` if the value was actually a quoteless string.
*/
bool tryParseNumber(Consumer)(ref string hjson, ref Consumer consumer)
{
    size_t i=0;
    bool parseAsDouble = false;

    // Optional preceding -
    if(hjson.front == '-') ++i;
    if(i >= hjson.length) 
        return false;

    // Integer part
    if(hjson[i] == '0') ++i;
    else if(hjson[i].isDecimalDigit)
        // Don't use countUntil because it returns -1 if no value 
        // in the range satisfies the condition
        i += hjson[i..$].until!(x => !x.isDecimalDigit).walkLength;
    else return false;

    // Fractional part
    if(i < hjson.length && hjson[i] == '.')
    {
        ++i;
        if(i >= hjson.length)
            return false;
        if(hjson[i].isDecimalDigit)
            i += hjson[i..$].until!(x => !x.isDecimalDigit).walkLength;
        else return false;
        parseAsDouble = true;
    }

    // Exponent part
    if(i < hjson.length && hjson[i].toLower == 'e')
    {
        ++i;
        if(i >= hjson.length) 
            return false;
        if(hjson[i] == '+' || hjson[i] == '-')
        {
            ++i;
            if(i >= hjson.length)
                return false;
        }
        if(hjson[i].isDecimalDigit)
            i += hjson[i..$].until!(x => !x.isDecimalDigit).walkLength;
        else return false;
        parseAsDouble = true;
    }
    
    if(turnsIntoQuotelessString(hjson[i..$]))
        return false;

    if(!parseAsDouble)
        try consumer.putValue(hjson[0..i].to!long);
        catch(ConvException) 
            parseAsDouble = true;

    if(parseAsDouble)
        consumer.putValue(hjson[0..i].to!double);

    hjson.popFrontN(i);
    return true;
}

/** Parses a HJSON quoteless string.
    Params:
        hjson = HJSON being parsed. Must not contain leading whitespace. 
                The beginning of the HJSON until the end of the parsed 
                HJSON value is consumed.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
    Returns: The parsed string.
*/
string parseQuotelessString(ref string hjson)
in(!hjson.empty)
{
    auto s = hjson.findSplitBefore("\n");
    hjson = s[1];
    auto result = s[0].stripRight!isWhite;
    assert(!result.empty);
    return result;
}

/** Parses a HJSON JSON-string.
    Params:
        hjson = HJSON being parsed. Must not contain leading whitespace. 
                The beginning of the HJSON until the end of the parsed 
                HJSON value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed. Will be updated by the function. 
                Needed to properly parse multiline strings.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
    Returns: The parsed string.
*/
string parseJSONString(ref string hjson, ref size_t collumn)
in(!hjson.empty)
in(hjson.front == '"' || hjson.front == '\'')
{
    immutable terminator = hjson.front;
    hjson.popFront();
    ++collumn;

    string result;

    while(!hjson.empty)
    {
        immutable c = hjson.front;
        hjson.popFront;
        ++collumn;

        if(c == '\n') collumn = 0;

        if(c == terminator)
        {
            return result;
        }
        else if(c == '\\')
        {
            enforce(!hjson.empty, "Incomplete escape sequence.");
            immutable d = hjson.front;
            hjson.popFront;
            ++collumn;
            switch(d)
            {
                case '"', '\'', '\\', '/': result ~= d; break;

                case 'b': result ~= '\b'; break;
                case 'f': result ~= '\f'; break;
                case 'n': result ~= '\n'; break;
                case 'r': result ~= '\r'; break;
                case 't': result ~= '\t'; break;

                case 'u': 
                    enforce(hjson.length >= 4, "Incomplete Unicode escape sequence.");
                    auto code = hjson[0..4];
                    enforce(code.all!isHexDigit, "Invalid Unicode escape sequence.");
                    result ~= cast(wchar) code.to!uint(16);
                    hjson.popFrontN(4);
                    collumn += 4;
                break;

                default: throw new HJSONException("Invalid escape sequence: \\%s".format(d));
            }
        }
        else result ~= c;
    }
    throw new HJSONException("Unterminated string literal.");
}

/** Parses a HJSON multiline string.
    Params:
        hjson = HJSON being parsed. Must not contain leading whitespace. 
                The beginning of the HJSON until the end of the parsed 
                HJSON value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON value.
    Invalid HJSON past the first valid value is not detected.
    Returns: The parsed string.
*/
string parseMultilineString(ref string hjson, immutable size_t collumn)
in(!hjson.empty)
in(hjson.save.startsWith("'''"))
{
    hjson.popFrontN(3);
    auto s = hjson.findSplit("'''");
    enforce(s[1] == "'''", "Unterminated multiline string (missing ''').");
    hjson = s[2];
    auto str = s[0];

    //If line with opening ''' contains only whitespace, ignore that whitespace
    auto prefixWhitespace = str.save.until!(x => !x.isWhite);
    if(prefixWhitespace.canFind('\n'))
        str = str.find('\n')[1..$];

    //Unindent
    string result;
    size_t ignoreWhitespace = collumn;
    foreach(x; str)
        if(x == '\n') 
        {
            ignoreWhitespace = collumn;
            result ~= x;
        }
        else if(x.isWhite && ignoreWhitespace > 0)
            --ignoreWhitespace;
        else 
        {
            ignoreWhitespace = 0;
            result ~= x;
        }

    // If sufix whitespace contains LF: remove it and all whitespace afterwards
    auto trailingWhitespace = result.retro.until!(x => !x.isWhite);
    if(trailingWhitespace.save.canFind('\n'))
        result.length = result.length - trailingWhitespace.countUntil('\n') - 1;

    return result;
}

/** Parses a single object member.
    Params:
        hjson = HJSON being parsed. Must not contain leading whitespace. 
                The beginning of the HJSON until the end of the parsed 
                HJSON object member is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed. Will be updated by the function. 
                Needed to properly parse multiline strings.
        consumer = Consumer used to construct the JSON object.
    Throws: 
    `HJSONException` if `hjson` starts with an invalid HJSON object member.
    Invalid HJSON past the first valid object member is not detected.
*/
void parseObjectMember(Consumer)(ref string hjson, ref size_t collumn, ref Consumer consumer)
{
    // Parse the key
    string key;
    enforce(!isPunctuator(hjson.front), "Expected HJSON member but got punctuator.");
    if(hjson.front == '"' || hjson.front == '\'') 
        key = hjson.parseJSONString(collumn);
    else {
        size_t keyLength = 0;
        while(
            keyLength < hjson.length && 
            !hjson[keyLength].isPunctuator && 
            !hjson[keyLength].isWhite
        ) ++keyLength;
        key = hjson[0..keyLength];
        hjson.popFrontN(keyLength);
        collumn += keyLength;
    }

    // Get rid of ':'
    hjson.skipWC(collumn);
    enforce(!hjson.empty);
    enforce(hjson.front == ':', "Expected ':'");
    hjson.popFront();
    ++collumn;

    // Parse the value
    hjson.skipWC(collumn);
    enforce(!hjson.empty);

    consumer.putKey(key);
    hjson.parseValue(collumn, consumer);
}

/** Consumes all whitespace and comments from the front of the passed HJSON.
    Params:
        hjson = HJSON from which whitespace and comments should be consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed. Will be updated by the function. 
                Needed to properly parse multiline strings.
    Throws:
    HJSONException if a block comment is not terminated before the end of the string.
    Returns:
    `true` if a line feed was skipped, `false` otherwise. This is needed because
    line feeds can be used to separate aggregate members similar to commas.
*/
bool skipWC(ref string hjson, ref size_t collumn)
{
    bool skippedLF = false;

    while(!hjson.empty)
    {
        bool finished = true;

        //Whitespace
        while(!hjson.empty && hjson.front.isWhite)
        {
            if(hjson.front == '\n')
            {
                skippedLF = true;
                collumn = 0;
            }
            else ++collumn;
            hjson.popFront;
            finished = false;
        }
        //Comments
        if(!hjson.empty)
        {
            if(hjson.front == '#' || hjson.save.startsWith("//")) 
            {
                hjson = hjson.find('\n');
                collumn = 0;
                finished = false;
            }
            else if(hjson.save.startsWith("/*"))
            {
                hjson.popFrontN(2);
                while(!hjson.save.startsWith("*/"))
                {
                    enforce(!hjson.empty, "Unterminated block comment (missing */)");
                    if(hjson.front == '\n') collumn = 0;
                    else ++collumn;
                    hjson.popFront;
                }
                hjson.popFrontN(2);
                collumn += 2;
                finished = false;
            }
        }
        if(finished) break;
    }
    return skippedLF;
}

/*@("skipWC") unittest
{
    string text = "  \t \r  ";
    assert(!skipWC(text));
    assert(text.empty);
    
    text = "    \t  hello";
    assert(!skipWC(text));
    assert(text == "hello");
    
    text = "  \n  ";
    assert(skipWC(text));
    assert(text.empty);
}*/

alias enforce = _enforce!HJSONException;

/** Checks whether given `dchar` is a HJSON punctuator.
    HJSON quoteless strings may not start with a punctuator,
    and quoteless object keys may not contain any punctuators.
*/
bool isPunctuator(dchar c)
{
    return "{}[],:"d.canFind(c);
}

version(unittest):
version(Have_unit_threaded):

import unit_threaded;
import std.json;

immutable readmeHjson = q"<
    // example.hjson
    {
        "name": "hjson",
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
>";

immutable readmeJson = q"<
    {
        "name": "hjson",
        "readable": {
            "omitQuotes": "This is a quoteless string",
            "omitCommas": [
                1,
                2,
                3
            ],
            "trailingCommas": {
                "a" : true,
                "b" : false,
                "c" : null
            },
            "multilineStrings": "Lorem\nipsum"
        }
    }
>";

@("readme") unittest
{
    readmeHjson.parseHJSON.should == readmeJson.parseJSON;
}

@("Direct HJSON to JSON conversion") unittest
{
    import asdf : jsonSerializer, parseJson;
    import std.array : appender;

    auto json = appender!string();
    auto serializer = jsonSerializer(&json.put!(const(char)[]));
    readmeHjson.parseHJSON(serializer);
    serializer.flush;

    json.data.parseJson.should == readmeJson.parseJson;
}