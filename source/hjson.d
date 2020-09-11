module hjson;

import std.json;
import std.typecons : Flag;
import std.array;
import std.range;
import std.algorithm;
import std.uni;
import std.ascii : isDecimalDigit = isDigit, isHexDigit;
import std.conv : to, ConvException;
import std.exception : basicExceptionCtors, _enforce = enforce;
import std.format : format;

JSONValue parseHJSON(string hjson)
{
    return hjson.parseValue();
}

private:

JSONValue parseValue(ref string hjson)
{
    hjson.skipWC();
    enforce(!hjson.empty, "Expected a value before EOF.");
    
    JSONValue result;
    if(hjson.front == '{')
    {
        result.object = null;
        hjson.parseAggregate!('{', '}', parseObjectMember)(result);
    }
    else if(hjson.front == '[')
    {
        result.array = [];
        hjson.parseAggregate!('[', ']', (ref hjson, ref arr){
            result.array ~= hjson.parseValue();
        })(result);
    }
    else if(hjson.save.startsWith("true"))
    {
        result = true;
        hjson.popFrontN("true".length);
    }
    else if(hjson.save.startsWith("false"))
    {
        result = false;
        hjson.popFrontN("false".length);
    }
    else if(hjson.save.startsWith("null"))
    {
        result = null;
        hjson.popFrontN("null".length);
    }
    else if(hjson.front == '"')
        result = hjson.parseJSONString();
    else if(hjson.front == '\'')
    {
        auto r = hjson.save;
        if(r.startsWith("'''"))
            result = hjson.parseMultilineString();
        else
            result = hjson.parseJSONString();
    }
    else if(!hjson.front.isPunctuator)
    {
        if(!hjson.tryParseNumber(result))
            result = hjson.parseQuotelessString();
    }
    else 
        throw new HJSONException("Invalid HJSON.");
    return result;
}

void parseAggregate
    (dchar start, dchar end, alias parseMember)
    (ref string hjson, ref JSONValue aggregate)
in(!hjson.empty)
in(hjson.front == start)
{
    // Get rid of opening '{' and whitespace
    hjson.popFront();
    hjson.skipWC();

    //Handle empty HJSON object {whitespace/comments only}
    enforce(!hjson.empty, "Expected member or '%s' before EOF.".format(end));
    if(hjson.front == end)
    {
        hjson.popFront();
        return;
    }

    //Now we know we have at least one member
    parseMember(hjson, aggregate);

    while(true)
    {
        // Skip member separator
        bool gotMemberSeparator = hjson.skipWC();
        enforce(!hjson.empty);
        if(hjson.front == ',')
        {
            hjson.popFront();
            gotMemberSeparator = true;
            hjson.skipWC();
            enforce(!hjson.empty);
        }

        if(hjson.front == end)
        {
            hjson.popFront();
            return;
        }
        else
        {
            enforce(gotMemberSeparator);
            parseMember(hjson, aggregate);
        }
    }
    assert(0, "Shouldn't get there");
}

bool tryParseNumber(ref string hjson, out JSONValue result)
{
    size_t i=0;
    bool parseAsDouble = false;

    // Optional preceding -
    if(hjson.front == '-') ++i;
    if(i >= hjson.length) 
        return false;

    // Integer part
    if(hjson[i] == 0) ++i;
    else if(hjson[i].isDecimalDigit)
        i += hjson[i..$].countUntil!(x => !x.isDecimalDigit);
    else return false;

    // Fractional part
    if(i < hjson.length && hjson[i] == '.')
    {
        ++i;
        if(i >= hjson.length)
            return false;
        if(hjson[i].isDecimalDigit)
            i += hjson[i..$].countUntil!(x => !x.isDecimalDigit);
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
            i += hjson[i..$].countUntil!(x => !x.isDecimalDigit);
        else return false;
        parseAsDouble = true;
    }
    
    // Try to detect cases when we start with a valid number, 
    // but then it turns out it's a quoteless string instead
    auto sufix = hjson[i..$];
    if(
        !sufix.empty &&
        sufix.front != ',' &&
        sufix.front != '\n'
    ) {
        // If there is a comment-starting token NOT SEPARATED BY WHITESPACE
        // then we treat the entire thing as quoteless string
        foreach(commentStart; ["//", "/*", "#"])
            if(sufix.startsWith(commentStart))
                return false;
        
        if(sufix.front.isWhite)
        {
            // We have whitespace after the number, but there is not-commented-out stuff
            // before the end of the line (we know because skipWC returned false),
            // so it's a quoteless string
            if(!skipWC(sufix))
                return false;
        }
        else return false; //number followed by non-whitespace, non-comma char -> quoteless string
    }

    if(!parseAsDouble)
        try result = hjson[0..i].to!long;
        catch(ConvException) 
            parseAsDouble = true;

    if(parseAsDouble)
        result = hjson[0..i].to!double;

    hjson.popFrontN(i);
    return true;
}

string parseQuotelessString(ref string hjson)
in(!hjson.empty)
{
    auto s = hjson.findSplitBefore("\n");
    hjson = s[1];
    auto result = s[0].stripRight!isWhite;
    assert(!result.empty);
    return result;
}

string parseJSONString(ref string hjson)
in(!hjson.empty)
in(hjson.front == '"' || hjson.front == '\'')
{
    immutable terminator = hjson.front;
    hjson.popFront();

    string result;

    while(!hjson.empty)
    {
        immutable c = hjson.front;
        hjson.popFront;

        if(c == terminator)
        {
            return result;
        }
        else if(c == '\\')
        {
            enforce(!hjson.empty, "Incomplete escape sequence.");
            immutable d = hjson.front;
            hjson.popFront;
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
                break;

                default: throw new HJSONException("Invalid escape sequence: \\%s".format(d));
            }
        }
        else result ~= c;
    }
    throw new HJSONException("Unterminated string literal.");
}

string parseMultilineString(ref string hjson)
in(!hjson.empty)
in(hjson.save.startsWith("'''"))
{
    hjson.popFrontN(3);
    auto s = hjson.findSplit("'''");
    enforce(s[1] == "'''", "Unterminated multiline string (missing ''').");
    hjson = s[2];
    
    auto result = s[0];
    return result;
}

void parseObjectMember(ref string hjson, ref JSONValue obj)
{
    // Parse the key
    string key;
    enforce(!isPunctuator(hjson.front), "Expected HJSON member but got punctuator.");
    if(hjson.front == '"' || hjson.front == '\'') 
        key = hjson.parseJSONString();
    else {
        size_t keyLength = 0;
        while(
            keyLength < hjson.length && 
            !hjson[keyLength].isPunctuator && 
            !hjson[keyLength].isWhite
        ) ++keyLength;
        key = hjson[0..keyLength];
        hjson.popFrontN(keyLength);
    }

    // Get rid of ':'
    hjson.skipWC();
    enforce(!hjson.empty);
    enforce(hjson.front == ':', "Expected ':'");
    hjson.popFront();

    // Parse the value
    hjson.skipWC();
    enforce(!hjson.empty);
    obj.object[key] = hjson.parseValue();
}

bool skipWC(ref string hjson)
{
    bool skippedLF = false;

    while(!hjson.empty)
    {
        bool finished = true;

        //Whitespace
        while(!hjson.empty && hjson.front.isWhite)
        {
            skippedLF = skippedLF || hjson.front == '\n';
            hjson.popFront;
            finished = false;
        }
        //Comments
        if(!hjson.empty)
        {
            if(hjson.front == '#' || hjson.save.startsWith("//")) 
            {
                hjson = hjson.find('\n');
                finished = false;
            }
            else if(hjson.save.startsWith("/*"))
            {
                hjson.popFrontN(2);
                hjson.findSkip!((a,b){
                    skippedLF = skippedLF || a=='\n'; 
                    return a==b;
                })("*/")
                    .enforce("Unterminated block comment (missing */)");
                finished = false;
            }
        }
        if(finished) break;
    }
    return skippedLF;
}

@("skipWC") unittest
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
}

class HJSONException : Exception
{
    mixin basicExceptionCtors;
}
alias enforce = _enforce!HJSONException;

bool isPunctuator(dchar c)
{
    return "{}[],:"d.canFind(c);
}