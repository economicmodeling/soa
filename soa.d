/**
 * Auto-reimplementation of array types from arrays of structures
 *  to structures of arrays.
 *
 * Author: Justin Whear
 */
module soa;

import std.traits : Unqual, isMutable, isArray;
import std.range : ElementType;

/**
 * Reimplements Array-of-Structs $(D A) as a Struct-of-Arrays.
 * Effectively does the following transformation:
----
// Array of structs
struct Vector3 {
	float x;
	float y;
	float z;
}
Vector3[100] vectors;

// Struct of arrays
struct Vector3_SOA {
	float[100] x;
	float[100] y;
}
Vector3_SOA vectors2;
----
 * This overload works with static arrays.  Provides slicing and indexing, as well
 *  as member access.
----
SOA!(Vector3[100]) vectors;
vectors[0].x = 100.0;
assert(vectors[0].x == 100.0);
vectors[1] = Vector3(2.0, 2.0, 2.0);
assert(vectors[1] == Vector3(2.0, 2.0, 2.0));

foreach (vec; vectors[0 .. 5])
	writeln(vec.x);
----
 * Note that the result of indexing (and the element type of the sliced range) is
 *  not the actual type parameterized on (e.g. Vector3), but rather a dispatching
 *  type.  The dispatching type does implement $(D opEquals) as well as a repacking
 *  $(opCast) to the original type.
 *
 * Access to the underlying contiguous arrays is available by using the member
 *  names on SOA type:
----
SOA!(Vector3[100]) vectors;
assert(is(typeof(vectors.x) == float[100]));
mySIMDInstruction(vectors.x, vectors.y);
----
 * 
 * The underlying static arrays are packed sequentially, so the SOA type can be
 *  reinterpreted via casts if desired:
----
SOA!(Vector3[2]) vectors;
vectors[0] = Vector3(1.0, 2.0, 3.0);
vectors[1] = Vector3(10.0, 20.0, 30.0);

// prove the data is actually packed SOA
auto fv = (cast(float*)&vectors)[0 .. vectors.length * 3];
assert(fv[0] == 1.0);   // x0
assert(fv[1] == 10.0);  // x1
assert(fv[2] == 2.0);   // y0
assert(fv[3] == 20.0);  // y1
assert(fv[4] == 3.0);   // z0
assert(fv[5] == 30.0);  // z1
----
 * Finally, static SOA types require no extra storage.  Dynamic SOA types incur
 *  the overhead inherent to dynamic array types for each member.
----
Vector3[2] a;
SOA!(typeof(b)) b;
static assert(typeof(a).sizeof == typeof(b).sizeof);
----
 */
struct SOA(A : T[N], T, size_t N) if (is(T == struct))
{
	mixin CommonImpl;

	// This string mixin is, unfortunately, the only way to initialize the member arrays
	private static string getMemberDecls() @property pure
	{
		string ret;
		foreach (name; __traits(allMembers, T))
			ret ~= `typeof(U.`~name~`)[N] `~name~` = initValues.`~name~`;`;
		return ret;
	}

	// Actual storage
	mixin(getMemberDecls);

	/// Array lengths
	static enum length = N;
}

/**
 * Ditto previous overload with a few notes.
 * 1) The length member may be set.  If grown, the added space in the member arrays
 *    will initialized to the appropriate member's initialization value.
 * 2) The member arrays ARE NOT contiguous with one another as in the case of 
 *    static array overload.  If this is desired, you may allocate these arrays
 *    yourself and set them:
----
SOA!(Vector3[]) vectors;
// allocation functions not actually supplied ;)
vectors.x = allocate();
vectors.y = allocateNextTo(vectors.x);
vectors.z = allocateNextTo(vectors.z);
----
 * 3) If you choose to tinker with the member arrays, you are responsible for
 *    ensuring that they all have equal lengths.
 */
struct SOA(A : T[], T) if (is(T == struct))
{
	mixin CommonImpl;

	private static string getMemberDecls() @property pure
	{
		string ret;
		foreach (name; __traits(allMembers, T))
			ret ~= `typeof(U.`~name~`)[] `~name~`;`;
		return ret;
	}

	// Actual storage
	mixin(getMemberDecls);

	/// Array lengths
	auto length() @property const
	{
		//TODO
		return __traits(getMember, this, "x").length;
	}

	///
	void length(size_t newLen) @property
	{
		auto oldLen = length;
		foreach (Name; __traits(allMembers, T))
		{
			__traits(getMember, this, Name).length = newLen;
			if (oldLen < newLen)
			{
				// initialize new values
				foreach (ref e; __traits(getMember, this, Name)[oldLen .. newLen])
					e = __traits(getMember, initValues, Name);
			}
		}
	}
}

// Static length SOA tests
unittest {
	struct Vector3
	{
		float x = 1, y = 4, z = 9;
	}

	import std.typetuple;
	import std.algorithm : equal;
	Vector3[3] witness;


	// Ensure that SOA of various types can be constructed and all expected operations work
	alias MutableTypes = TypeTuple!(Vector3[3]);
	alias ImmutableTypes = TypeTuple!(
		const(Vector3)[3],
		const(Vector3[3])
	);
	foreach (B; TypeTuple!(MutableTypes, ImmutableTypes))
	{
		SOA!(B) b;
		static assert(typeof(b).sizeof == typeof(witness).sizeof);

		// Ensure storage is actually SOA by checking the underlying memory
		auto fv = (cast(float*)&b)[0 .. b.length * Vector3.tupleof.length];
		assert(fv[0 .. 3].equal([1,1,1])); // x's are all 1
		assert(fv[3 .. 6].equal([4,4,4])); // y's are all 4
		assert(fv[6 .. 9].equal([9,9,9])); // z's are all 9

		// Test memberwise access
		foreach (i, wEl; witness)
		{
			assert(wEl.x == b[i].x);
			assert(wEl.y == b[i].y);
			assert(wEl.z == b[i].z);
		}

		// test opEquals with original type
		assert(witness[0] == b[0]);
		assert(witness[].equal(b[]));

		// test opEquals with Dispatch type
		assert(b[0] == b[1]);
		assert(b[].equal(b[]));

	}

	foreach (B; MutableTypes)
	{
		SOA!(B) b;

		// Test setting
		b[0].x = 11;
		b[1].y = 21;
		b[2].z = 31;
		assert(b[0].x == 11);
		assert(b[1].y == 21);
		assert(b[2].z == 31);

		// Or whole Vector at a time
		b[0] = Vector3(3.0,4,5);
		assert(b[0] == Vector3(3.0,4,5));
	}

	SOA!(Vector3[2]) vectors;
	vectors[0] = Vector3(1.0, 2.0, 3.0);
	vectors[1] = Vector3(10.0, 20.0, 30.0);

	auto fv = (cast(float*)&vectors)[0 .. vectors.length * 3];
	assert(fv[0] == 1.0);   // x0
	assert(fv[1] == 10.0);  // x1
	assert(fv[2] == 2.0);   // y0
	assert(fv[3] == 20.0);  // y1
	assert(fv[4] == 3.0);   // z0
	assert(fv[5] == 30.0);  // z1
}

// Dynamic length SOA tests
unittest {
	struct Vector3
	{
		float x = 1, y = 4, z = 9;
	}

	import std.typetuple;
	import std.algorithm : equal;
	Vector3[] witness = [Vector3(), Vector3(), Vector3()];


	// Ensure that SOA of various types can be constructed and all expected operations work
	alias MutableTypes = TypeTuple!(Vector3[]);
	alias ImmutableTypes = TypeTuple!(
		const(Vector3)[],
		const(Vector3[])
	);
	foreach (B; TypeTuple!(MutableTypes, ImmutableTypes))
	{
		SOA!(B) b;
		b.length = 3;

		// Ensure storage is actually SOA by checking the underlying memory
		//NOTE THAT THE FIELD ARRAYS ARE NOT THEMSELVES CONTIGUOUS AS WITH THE
		// STATIC VERSION
		assert(b.x == [1, 1, 1]);
		assert(b.y == [4, 4, 4]);
		assert(b.z == [9, 9, 9]);


		// Test memberwise access
		foreach (i, wEl; witness)
		{
			assert(wEl.x == b[i].x);
			assert(wEl.y == b[i].y);
			assert(wEl.z == b[i].z);
		}

		// test opEquals with original type
		assert(witness[0] == b[0]);
		assert(witness[].equal(b[]));

		// test opEquals with Dispatch type
		assert(b[0] == b[1]);
		assert(b[].equal(b[]));
	}

	foreach (B; MutableTypes)
	{
		SOA!(B) b;
		b.length = 3;

		// Test setting
		b[0].x = 11;
		b[1].y = 21;
		b[2].z = 31;
		assert(b[0].x == 11);
		assert(b[1].y == 21);
		assert(b[2].z == 31);

		// Or whole Vector at a time
		b[0] = Vector3(3.0,4,5);
		assert(b[0] == Vector3(3.0,4,5));
	}
}


// This implementation is identical between the static and dynamic versions
private mixin template CommonImpl()
{
	alias U = Unqual!T;

	// This is required to initialize the arrays to corresponding init values from
	//  the user's T definition
	private static enum T initValues = T.init;

	/// Provides element access just like original AOS type
	auto ref opIndex(size_t i) pure
	{
		alias Parent = typeof(this);

		// Dispatches `.x`, etc. to parent.x[i]
		static struct Dispatcher
		{
			Parent* parent;
			const size_t idx;

			// Support `a[0].x`
			auto opDispatch(string op)() @property const pure
			{
				return __traits(getMember, parent, op)[idx];
			}

			// Support `a[0].x = y`
			static if (isMutable!T)
			void opDispatch(string op, V)(V newVal) @property
			{
				__traits(getMember, parent, op)[idx] = newVal;
			}

			// Check equality with other instances of this Dispatch type
			bool opEquals()(auto ref const typeof(this) v) const
			{
				foreach (Name; __traits(allMembers, T))
					if (__traits(getMember, v, Name) != opDispatch!Name) return false;
				return true;
			}

			// Check equality with the original type
			bool opEquals()(auto ref const U v) const
			{
				// statically unrolled
				foreach (Name; __traits(allMembers, T))
					if (__traits(getMember, v, Name) != opDispatch!Name) return false;
				return true;
			}

			/// Assign from original structure type
			static if (isMutable!T)
			void opAssign(T v)
			{
				// statically unrolled
				foreach (Name; __traits(allMembers, T))
					opDispatch!Name(__traits(getMember, v, Name));
			}

			/// Repacks to the original structure type
			T opCast(T)()
			{
				U ret;
				foreach (Name; __traits(allMembers, U))
					__traits(getMember, ret, Name) = opDispatch!Name;
				return cast(T)ret;
			}
		}
		return Dispatcher(&this, i);
	}

	///
	auto opSlice()
	{
		return this[0 .. length];
	}

	///
	auto opSlice(size_t s, size_t e)
	{
		import std.range, std.algorithm;
		return iota(s, e).map!(n => this.opIndex(n));
	}
}
