module hjson_tests;

version(unittest):

import std.json;
import std.stdio : writeln;
import unit_threaded;
import hjson;


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
]) 
@testName unittest 
{
    string json = import(testName~"_result.json"),
           hjsonResult = import(testName~"_result.hjson"),
           hjsonTest = import(testName~"_test.hjson");


    hjsonTest.parseHJSON.should == json.parseJSON;
    hjsonResult.parseHJSON.should == json.parseJSON;
    json.parseHJSON.should == json.parseJSON;
}

static foreach(testName; [
    "mltabs",
    "pass1",
    "pass2",
    "pass3",
    "pass4"
]) 
@testName unittest 
{
    string hjson = import(testName~"_result.hjson"),
           json = import(testName~"_result.json");

    hjson.parseHJSON.should == json.parseJSON;
    json.parseHJSON.should == json.parseJSON;
}