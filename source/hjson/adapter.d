module hjson.adapter;

package(hjson):

import std.json : JSONValue, JSONType, JSONException;

struct StdJsonSerializer
{
    pure @system:

    JSONValue* result;

    uint objectBegin()
    {
        if(noRootAggregate)
        {
            result.object = null;
            push(result);
        }
        else 
        {
            JSONValue obj;
            obj.object = null;
            
            if(top.type == JSONType.object)
            {
                top.object[key] = obj;
                push(&top.object[key]);
            }
            else
            {
                top.array ~= obj;
                push(&top.array[$-1]);
            }
        }
        return 0;
    }

    void objectEnd(uint state)
    in(!noRootAggregate && top.type == JSONType.object)
    {
        pop();
    }

    uint arrayBegin()
    {
        if(noRootAggregate)
        {
            result.array = [];
            push(result);
        }
        else
        {
            JSONValue arr;
            arr.array = [];
            if(top.type == JSONType.object)
            {
                top.object[key] = arr;
                push(&top.object[key]);
            }
            else
            {
                top.array ~= arr;
                push(&top.array[$-1]);
            }
        }
        return 0;
    }

    void arrayEnd(size_t state)
    in(!noRootAggregate && top.type == JSONType.array)
    {
        pop();
    }

    void putKey(const char[] key)
    {
        this.key = key;
    }
    void putValue(T)(T value)
    {
        if(noRootAggregate) 
            *result = value;
        else if(top.type == JSONType.object)
            top.object[key] = JSONValue(value);
        else top.array ~= JSONValue(value);
    }
    void elemBegin() {}
    void flush() {} 

    private:

    void push(JSONValue* value){stack ~= value;}
    ref inout(JSONValue) top() inout {return *(stack[$-1]);}
    void pop() {stack.length = stack.length-1;}
    bool noRootAggregate() const {return stack.length == 0;}

    JSONValue*[] stack;
    const(char)[] key;

    invariant(
        noRootAggregate || 
        top.type == JSONType.object || 
        top.type == JSONType.array
    );
}

version(unittest):
version(Have_unit_threaded):

import unit_threaded;

@("StdJsonSerializer")
unittest
{
    import std.json : parseJSON, JSONValue;

    JSONValue value;
    auto ser = StdJsonSerializer(&value);
    auto o = ser.objectBegin();
        ser.putKey("hello"); ser.putValue("world");
        ser.putKey("foo"); ser.putValue(1234);
        ser.putKey("null"); ser.putValue(null);
        ser.putKey("array");
        auto a = ser.arrayBegin();
            ser.elemBegin; ser.putValue(1);
            ser.elemBegin; ser.putValue("abc");
            ser.elemBegin; ser.putValue(false);
        ser.arrayEnd(a);
        ser.putKey("afterArray"); ser.putValue(42);
    ser.objectEnd(o);

    value.should == parseJSON(q"<
        {
            "hello" : "world",
            "foo" : 1234,
            "null" : null,
            "array" : [1, "abc", false],
            "afterArray" : 42
        }
    >");
}