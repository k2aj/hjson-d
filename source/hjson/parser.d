module hjson.parser;

public import std.json : JSONValue;

import std.algorithm;
import std.array;
import std.ascii : isDecimalDigit = isDigit, isHexDigit;
import std.conv : ConvException, to;
import std.exception : _enforce = enforce, basicExceptionCtors;
import std.format : format;
import std.range;
import std.typecons : Flag;
import std.uni;

import hjson.adapter;

/** Parses a Hjson value into a `JSONValue` object.
    Params:
        hjson = string containing the Hjson.
    Throws:
        `HjsonException` when passed invalid Hjson.
    Returns:
        Parsed JSONValue.
*/
JSONValue parseHjson(string hjson)
{
    JSONValue result;
    scope consumer = StdJsonSerializer(&result);
    hjson.parseHjson(consumer);
    return result;
}

/** Parses a Hjson value and feeds the parsed tokens into given consumer.
    This allows for parsing into representations other than std.json.JSONValue.
    Params:
        hjson = string containing the Hjson.
        consumer = Object responsible for processing the parsed tokens.
    Throws:
        `HjsonException` when passed invalid Hjson.
*/
void parseHjson(Consumer)(string hjson, ref Consumer consumer)
{
    size_t collumn = 0;
    hjson.parseValue(collumn,consumer);
}

///
class HjsonException : Exception
{
    mixin basicExceptionCtors;
}

/** Parses a single Hjson value (object, array, string, number, bool or null).
    Params:
        hjson = string being parsed. May contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                Hjson value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                  last line feed. Will be updated by the function. 
                  Needed to properly parse multiline strings.
        consumer = Object responsible for processing the parsed tokens.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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
    else throw new HjsonException("Invalid Hjson.");
}

/** Parses a single Hjson object or array.
    Params:
        hjson = string being parsed. Must not contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                Hjson value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                  last line feed. Will be updated by the function. 
                  Needed to properly parse multiline strings.
        consumer = Object responsible for processing the parsed tokens.
        start = Token which marks the beginning of parsed aggregate ('[' for array, '{' for object)
        end = Token which marks the end of parsed aggregate (']' for array, '}' for object)
        parseMember = Function used to parse a single aggregate member. Parameters are
                      the same as `parseAggregate`. Hjson passed to `parseMember` contains
                      no leading whitespace.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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

    //Handle empty Hjson object {whitespace/comments only}
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
    first character. In Hjson if you follow a valid JSON number/bool/null with certain other
    characters it will turn into a quoteless string. This function checks whether parsed
    value turns into a quoteless string by looking at the following characters.

    Params:
        sufix = Hjson following the previously parsed value.
    Returns: Whether `sufix` turns the preceding Hjson number/bool/null into a quoteless string.
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
                Hjson value is consumed if and only if the constant was
                succesfully parsed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                  last line feed. Will be updated by the function. 
                  Needed to properly parse multiline strings.
        value = Value of the constant.
        repr = How the constant is represented in Hjson.
        consumer = Object responsible for processing the parsed tokens.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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

/** Attempts to parse a Hjson number.
    Params:
        hjson = string being parsed. Must not contain leading whitespace. 
                The beginning of the string until the end of the parsed 
                Hjson value is consumed if and only if the number was
                succesfully parsed.
        consumer = Object responsible for processing the parsed tokens.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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

/** Parses a Hjson quoteless string.
    Params:
        hjson = Hjson being parsed. Must not contain leading whitespace. 
                The beginning of the Hjson until the end of the parsed 
                Hjson value is consumed.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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

/** Parses a Hjson JSON-string.
    Params:
        hjson = Hjson being parsed. Must not contain leading whitespace. 
                The beginning of the Hjson until the end of the parsed 
                Hjson value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed. Will be updated by the function. 
                Needed to properly parse multiline strings.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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

                default: throw new HjsonException("Invalid escape sequence: \\%s".format(d));
            }
        }
        else result ~= c;
    }
    throw new HjsonException("Unterminated string literal.");
}

/** Parses a Hjson multiline string.
    Params:
        hjson = Hjson being parsed. Must not contain leading whitespace. 
                The beginning of the Hjson until the end of the parsed 
                Hjson value is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson value.
    Invalid Hjson past the first valid value is not detected.
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
        hjson = Hjson being parsed. Must not contain leading whitespace. 
                The beginning of the Hjson until the end of the parsed 
                Hjson object member is consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed. Will be updated by the function. 
                Needed to properly parse multiline strings.
        consumer = Object responsible for processing the parsed tokens.
    Throws: 
    `HjsonException` if `hjson` starts with an invalid Hjson object member.
    Invalid Hjson past the first valid object member is not detected.
*/
void parseObjectMember(Consumer)(ref string hjson, ref size_t collumn, ref Consumer consumer)
{
    // Parse the key
    string key;
    enforce(!isPunctuator(hjson.front), "Expected Hjson member but got punctuator.");
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

/** Consumes all whitespace and comments from the front of the passed Hjson.
    Params:
        hjson = Hjson from which whitespace and comments should be consumed.
        collumn = How many `dchar`s were popped from the front of `hjson` since
                last line feed. Will be updated by the function. 
                Needed to properly parse multiline strings.
    Throws:
    HjsonException if a block comment is not terminated before the end of the string.
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

alias enforce = _enforce!HjsonException;

/** Checks whether given `dchar` is a Hjson punctuator.
    Hjson quoteless strings may not start with a punctuator,
    and quoteless object keys may not contain any punctuators.
*/
bool isPunctuator(dchar c)
{
    return "{}[],:"d.canFind(c);
}

version(unittest):
version(Have_unit_threaded):

import std.format : format;
import std.json : parseJSON;
import std.range : chain, only, iota;

import unit_threaded;

static foreach(testName; [
    "charset",
    "charset2",
    "comments",
    "empty",
    "kan",
    "keys",
    "oa",
    "passSingle",
    "stringify1",
    "strings",
    "strings2",
    "trail"
]) {
    @testName unittest 
    {
        immutable json = import(testName~"_result.json"),
            hjsonResult = import(testName~"_result.hjson"),
            hjsonTest = import(testName~"_test.hjson");

        hjsonTest.parseHjson.should == json.parseJSON;
        hjsonResult.parseHjson.should == json.parseJSON;
        json.parseHjson.should == json.parseJSON;
    }
}
static foreach(testName; [
    "mltabs",
    "pass1",
    "pass2",
    "pass3",
    "pass4"
]) {
    @testName unittest 
    {
        immutable hjson = import(testName~"_result.hjson"),
            json = import(testName~"_result.json");

        hjson.parseHjson.should == json.parseJSON;
        json.parseHjson.should == json.parseJSON;
    }
}

static foreach(failNr; chain(
    only(2),
    iota(5,7),
    iota(11,18),
    iota(19,24),
    only(26),
    iota(28,34)
)) {
    @Tags("invalid_input")
    @format("failJSON%d", failNr) unittest 
    {
        immutable json = import("failJSON%02d_test.json".format(failNr));
        json.parseHjson.shouldThrow!HjsonException;
    }
}

static foreach(failNr; [7,8,10,34])
{
    @Tags("invalid_input")
    @ShouldFail("Hjson-d does not attempt to validate the rest of input after parsing a valid Hjson value.")
    @format("failJSON%d", failNr) unittest 
    {
        immutable json = import("failJSON%02d_test.json".format(failNr));
        json.parseHjson.shouldThrow!HjsonException;
    }
}