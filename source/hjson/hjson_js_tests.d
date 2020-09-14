/// This module runs unit tests copied from HJSON-JS.
module hjson.hjson_js_tests;

version(unittest):
version(Have_unit_threaded):

import std.format;
import std.json;
import std.range;
import std.stdio : writeln;

import asdf : asdfSerializer, parseJsonToAsdf = parseJson, Asdf;
import hjson;
import unit_threaded;

Asdf parseHjsonToAsdf(string hjson)
{
    auto consumer = asdfSerializer();
    hjson.parseHJSON(consumer);
    return consumer.app.result;
}

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
        string json = import(testName~"_result.json"),
            hjsonResult = import(testName~"_result.hjson"),
            hjsonTest = import(testName~"_test.hjson");

        hjsonTest.parseHJSON.should == json.parseJSON;
        hjsonResult.parseHJSON.should == json.parseJSON;
        json.parseHJSON.should == json.parseJSON;
    }
    @Tags("asdf_interop")
    @(testName~"-asdf") unittest
    {
        string json = import(testName~"_result.json"),
            hjsonResult = import(testName~"_result.hjson"),
            hjsonTest = import(testName~"_test.hjson");

        hjsonTest.parseHjsonToAsdf.should == json.parseJsonToAsdf;
        hjsonResult.parseHjsonToAsdf.should == json.parseJsonToAsdf;
        json.parseHjsonToAsdf.should == json.parseJsonToAsdf;
    }
}
static foreach(testName; [
    "mltabs",
    "pass2",
    "pass3",
    "pass4"
]) {
    @testName unittest 
    {
        string hjson = import(testName~"_result.hjson"),
            json = import(testName~"_result.json");

        hjson.parseHJSON.should == json.parseJSON;
        json.parseHJSON.should == json.parseJSON;
    }

    @Tags("asdf_interop")
    @(testName~"-asdf") unittest
    {
        string hjson = import(testName~"_result.hjson"),
            json = import(testName~"_result.json");
        
        hjson.parseHjsonToAsdf.should == json.parseJsonToAsdf;
        json.parseHjsonToAsdf.should == json.parseJsonToAsdf;
    }
}

@("pass1") unittest 
{
    string hjson = import("pass1_result.hjson"),
        json = import("pass1_result.json");

    hjson.parseHJSON.should == json.parseJSON;
    json.parseHJSON.should == json.parseJSON;
}

@Tags("asdf_interop")
@ShouldFail("This fails because ASDF parses doubles at higher precision than std.conv.to")
@("pass1-asdf") unittest
{
    string hjson = import("pass1_result.hjson"),
        json = import("pass1_result.json");
    
    hjson.parseHjsonToAsdf.should == json.parseJsonToAsdf;
    json.parseHjsonToAsdf.should == json.parseJsonToAsdf;
}

/* Tests 7,8,10 and 34 are excluded because they test detecting bad input placed after a valid
   HJSON value (and parseHJSON will not attempt to consume further input after reading a valid value).
*/
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
        string json = import("failJSON%02d_test.json".format(failNr));
        json.parseHJSON.shouldThrow!HJSONException;
    }
}
