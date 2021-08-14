# Simple Undo / Redo History in [Odin](http://odin-lang.org/)
Pretty much [this by rxi](https://rxi.github.io/a_simple_undo_system.html)

## How it works
1. Push pointers / slices that you expect to change
2. Commit at some point, comparisons are done on the pointers / slices from their push to current state
3. A valid commit with changes is appended as an undo step
4. Call undo 

## Example Test Simple 
```go 
package main

import hist "shared:simple-history"

main :: proc() {
	using hist;
	
	history: History;
	init(&history);
	defer destroy(&history);
	
	a: int;
	push(&history, &a);
	push(&history, &a); // will be ignored since &a exists in temp already
	a = 1;
	commit(&history, "A");
	
	b: int;
	push(&history, &b);
	b = 1;
	commit(&history, "B");
	
	fmt.println("--- TEST SIMPLE ---");
	fmt.println("START", a, b);
	fmt.println(undo(&history), a, b);
	fmt.println(undo(&history), a, b);
	fmt.println(redo(&history), a, b);
	fmt.println(redo(&history), a, b);
	fmt.println(undo(&history), a, b);
	fmt.println(undo(&history), a, b);
	fmt.println(undo(&history), a, b);
	
	// --- TEST SIMPLE ---
	// START 1 1
	// true 1 0
	// true 0 0
	// true 1 0
	// true 1 1
	// true 1 0
	// true 0 0
	// false 0 0
}
```

## Try out
Clone the repository to your `Odin/shared` folder and try out the `_test_*` calls, they are a good showcase of how the library works: 
```go
package main

import history "shared:simple-history"

main :: proc() {
    history._test_simple();
    history._test_ptrs();
    history._test_complex();
}
```

## Global Wrapper
If you only plan on using a global undo / redo history you can do a wrapper like, make sure to `init / destroy` the global somewhere:
```go
import history "shared:simple-history"

_history: history.History;

hpush :: #force_inline proc(ptr: ^$T) {
	history.push(&_history, ptr);
}

hslice :: #force_inline proc(slice: []$T) {
	history.push_slice(&_history, slice);
}

hcommit :: #force_inline proc(action: string) {
	history.commit(&_history, action);
}

hundo :: #force_inline proc() -> bool {
	return history.undo(&_history);
}

hredo :: #force_inline proc() -> bool {
	return history.redo(&_history);
}
```

## What next?
This is enough in my usecases, you could probably try and support more `odin` types like `map`
One thing I avoid is resizable containers like `[dynamic]`, they will change their `data: ^T` location which could make undo / redo changes invalid, since they might be based on the old data location 

