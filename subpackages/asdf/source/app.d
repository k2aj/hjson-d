version(unittest)
{
	version(Have_unit_threaded)
	{
		import unit_threaded;
		mixin runTestsMain!(
			"hjson.asdf"
		);
	}
}