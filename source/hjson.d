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
    size_t collumn = 0;
    return hjson.parseValue(collumn);
}

private:

JSONValue parseValue(ref string hjson, ref size_t collumn)
{
    hjson.skipWC(collumn);
    enforce(!hjson.empty, "Expected a value before EOF.");
    
    JSONValue result;
    if(hjson.front == '{')
    {
        result.object = null;
        hjson.parseAggregate!('{', '}', parseObjectMember)(collumn, result);
    }
    else if(hjson.front == '[')
    {
        result.array = [];
        hjson.parseAggregate!('[', ']', (ref hjs, ref col, ref arr){
            result.array ~= hjs.parseValue(col);
        })(collumn,result);
    }
    else if(hjson.save.startsWith("true"))
    {
        if(!hjson.tryParseBuiltin(collumn,true,"true",result))
            result = hjson.parseQuotelessString();
    }
    else if(hjson.save.startsWith("false"))
    {
        if(!hjson.tryParseBuiltin(collumn,false,"false",result))
            result = hjson.parseQuotelessString();
    }
    else if(hjson.save.startsWith("null"))
    {
        if(!hjson.tryParseBuiltin(collumn,null,"null",result))
            result = hjson.parseQuotelessString();
    }
    else if(hjson.front == '"')
        result = hjson.parseJSONString(collumn);
    else if(hjson.front == '\'')
    {
        auto r = hjson.save;
        if(r.startsWith("'''"))
            result = hjson.parseMultilineString(collumn);
        else
            result = hjson.parseJSONString(collumn);
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
    (ref string hjson, ref size_t collumn, ref JSONValue aggregate)
in(!hjson.empty)
in(hjson.front == start)
{
    import std.stdio;
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
    parseMember(hjson, collumn, aggregate);

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
            parseMember(hjson, collumn, aggregate);
        }
    }
    assert(0, "Shouldn't get there");
}

bool turnsIntoQuotelessString(string sufix)
{
    if(
        !sufix.empty &&
        !sufix.front.isPunctuator &&
        sufix.front != '\n'
    ) {
        // If there is a comment-starting token NOT SEPARATED BY WHITESPACE
        // then we treat the entire thing as quoteless string
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

bool tryParseBuiltin(T)(ref string hjson, ref size_t collumn, T value, string repr, out JSONValue result)
{
    auto sufix = hjson[repr.length..$];
    if(turnsIntoQuotelessString(sufix)) return false;
    else 
    {
        result = value;
        hjson = sufix;
        collumn += repr.walkLength;
        return true;
    }
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

void parseObjectMember(ref string hjson, ref size_t collumn, ref JSONValue obj)
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
    obj.object[key] = hjson.parseValue(collumn);
}

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

class HJSONException : Exception
{
    mixin basicExceptionCtors;
}
alias enforce = _enforce!HJSONException;

bool isPunctuator(dchar c)
{
    return "{}[],:"d.canFind(c);
}