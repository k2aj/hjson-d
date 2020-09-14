module hjson.asdf;

public import asdf.asdf : Asdf;

/** Parses a Hjson value into ASDF representation.
    Params:
        hjson = string containing the Hjson.
    Throws:
        `HjsonException` when passed invalid Hjson.
    Returns:
        ASDF containing the parsed Hjson value.
*/
Asdf parseHjsonToAsdf(string hjson)
{
    import asdf.serialization : asdfSerializer;
    import hjson.parser : parseHjson;

    auto serializer = asdfSerializer();
    hjson.parseHjson(serializer);
    return serializer.app.result;
}

/** Converts a single Hjson value directly into JSON.
    Params:
        hjson = Hjson to convert.
    Throws:
        `HjsonException` when passed invalid Hjson.
    Returns:
        `hjson` converted into JSON.
*/
string hjsonToJson(string hjson)
{
    import asdf.serialization : jsonSerializer;
    import hjson.parser : parseHjson;
    import std.array : appender;

    auto app = appender!string();
    auto serializer = jsonSerializer(&app.put!(const(char)[]));
    hjson.parseHjson(serializer);
    serializer.flush;

    return app.data;
}

version(unittest):
version(Have_unit_threaded):

import std.format : format;
import asdf.jsonparser : parseJson;
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
    @Tags("asdf")
    @(testName~"-parsing") unittest
    {
        immutable json = import(testName~"_result.json"),
            hjsonResult = import(testName~"_result.hjson"),
            hjsonTest = import(testName~"_test.hjson");

        hjsonTest.parseHjsonToAsdf.should == json.parseJson;
        hjsonResult.parseHjsonToAsdf.should == json.parseJson;
        json.parseHjsonToAsdf.should == json.parseJson;
    }

    @Tags("asdf")
    @(testName~"-conversion") unittest
    {
        immutable json = import(testName~"_result.json"),
            hjsonResult = import(testName~"_result.hjson"),
            hjsonTest = import(testName~"_test.hjson");

        hjsonTest.hjsonToJson.parseJson.should == json.parseJson;
        hjsonResult.hjsonToJson.parseJson.should == json.parseJson;
        json.hjsonToJson.parseJson.should == json.parseJson;
    }
}
static foreach(testName; [
    "mltabs",
    "pass2",
    "pass3",
    "pass4"
]) {
    @Tags("asdf")
    @(testName~"-parsing")unittest
    {
        immutable hjson = import(testName~"_result.hjson"),
            json = import(testName~"_result.json");
        
        hjson.parseHjsonToAsdf.should == json.parseJson;
        json.parseHjsonToAsdf.should == json.parseJson;
    }

    @Tags("asdf")
    @(testName~"-conversion") unittest
    {
        immutable hjson = import(testName~"_result.hjson"),
            json = import(testName~"_result.json");
        
        hjson.hjsonToJson.parseJson.should == json.parseJson;
        json.hjsonToJson.parseJson.should == json.parseJson;
    }
}

@Tags("asdf")
@ShouldFail("This fails because ASDF parses doubles at higher precision than std.conv.to")
@("pass1-parsing") unittest
{
    immutable hjson = import("pass1_result.hjson"),
        json = import("pass1_result.json");
    
    hjson.parseHjsonToAsdf.should == json.parseJson;
    json.parseHjsonToAsdf.should == json.parseJson;
}