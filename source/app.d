import std.stdio;



version(unittest)
{
	version(Have_unit_threaded)
	{
		import unit_threaded;
		mixin runTestsMain!(
			"hjson.parser",
			"hjson.hjson_js_tests"
		);
	}
}
else
{
	import hjson;

	void main()
	{
		auto hjson = q"<
		{
			// Doesn't work yet!
			name: Joe Albert    
			surname: "Schreier",
			age: 42 /*Sneaky multiline comment
			*/ family: {
				mother: {
					"name" : 'Alice'
					surname: null
				}
				father: {
					name: Bob
					surname: 1337.42e+69#this is actually not a number, nor a comment
					job: FBI agent
				},
			}
			friends: [{name: "haha nope"}, {}, {null:null}, null,]

			#Well duh...
			alive: true 

			biography: '''
				public class HelloWorld {
					// Haha Java go brr
					public static void main(String[] args) {
						System.out.println("Hello, world!");
					}
				}
			'''
		}>";
	}
}
