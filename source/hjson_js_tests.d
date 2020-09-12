/// This module runs unit tests copied from HJSON-JS.
module hjson_js_tests;

version(unittest):
version(Have_unit_threaded):

import std.json;
import std.stdio : writeln;
import unit_threaded;
import hjson;
import std.range;
import std.format;

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
        string hjson = import(testName~"_result.hjson"),
            json = import(testName~"_result.json");

        hjson.parseHJSON.should == json.parseJSON;
        json.parseHJSON.should == json.parseJSON;
    }
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
