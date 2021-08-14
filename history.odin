package history

import "core:fmt"
import "core:mem"
import "core:container"

TempMap :: map[rawptr][]byte;

History :: struct {
	temp: TempMap,
	undo, redo: container.Array(HistoryBatch),
	// used to store temporary undo / redo bytes, size should be the max size of something you plan to store
	flip: []byte,
	allocator: mem.Allocator,
}

// one undo step - batch of changes
HistoryBatch :: struct {
	changes: [dynamic]HistoryChange,
	name: string,
}

// one undo change with its previous state + ptr location
HistoryChange :: struct {
	bytes: []byte,
	ptr: rawptr,
}

// clear temporary assigned pushes
clear_temp :: proc(a: ^History) {
	for ptr, arr in a.temp {
		delete(arr);
	}

	clear(&a.temp);
}

init :: proc(a: ^History, undo_max := 64, redo_max := 64, flip_bytes_max := 1024, temp_max := 32, allocator := context.allocator) {
	a.allocator = allocator;
	container.array_init_len_cap(&a.undo, 0, undo_max, allocator);
	container.array_init_len_cap(&a.redo, 0, redo_max, allocator);
	a.flip = make([]byte, flip_bytes_max, allocator);
	a.temp = make(TempMap, temp_max, allocator);
}

destroy :: proc(a: ^History) {
	_array_free(a, &a.undo);
	_array_free(a, &a.redo);
	
	container.array_delete(a.undo);
	container.array_delete(a.redo);
	
	for ptr, arr in a.temp {
		delete(arr, a.allocator);
	}

	delete(a.temp);
	delete(a.flip, a.allocator);
}

_array_free :: proc(a: ^History, array: ^container.Array(HistoryBatch)) {
	for i in 0..<array.len {
		batch := container.array_get_ptr(array^, i);
		
		for change in &batch.changes {
			delete(change.bytes, a.allocator);
		}

		delete(batch.changes);
	}
	
	container.array_clear(array);
}

push :: proc(a: ^History, ptr: ^$T) {
	if ptr not_in a.temp {
		bytes := make([]byte, size_of(T), a.allocator);
		mem.copy(&bytes[0], ptr, size_of(T));
		a.temp[ptr] = bytes;
	}
}

push_slice :: proc(a: ^History, slice: []$T) {
	if len(slice) == 0 do return;
	
	if &slice[0] not_in a.temp {
		bytes := make([]byte, size_of(T) * len(slice), a.allocator);
		mem.copy(&bytes[0], &slice[0], size_of(T) * len(slice));
		a.temp[&slice[0]] = bytes;
	}
}

commit :: proc(a: ^History, name: string) {
	if len(a.temp) == 0 {
		return;
	}
	
	batch: HistoryBatch;
	any_change: bool;
	
	for ptr, bytes in a.temp {
		if mem.compare(bytes[:], mem.byte_slice(ptr, len(bytes))) != 0 {
			append(&batch.changes, HistoryChange { bytes, ptr });
			any_change = true;
		} else {
			delete(bytes);
		}
	}
	
	if any_change {
		_array_free(a, &a.redo);
		batch.name = name;
		container.array_push_back(&a.undo, batch);
	}
	
	clear(&a.temp);
}

undo :: #force_inline proc(a: ^History) -> bool {
	return _undo_redo(a, &a.undo, &a.redo);
}

redo :: #force_inline proc(a: ^History) -> bool {
	return _undo_redo(a, &a.redo, &a.undo);
}

_undo_redo :: proc(history: ^History, a, b: ^container.Array(HistoryBatch)) -> bool {
	commit(history, "SaveCommit");
	
	if a.len == 0 {
		return false;
	}
	
	batch := container.array_pop_back(a);
	
	for i := len(batch.changes) - 1; i >= 0; i -= 1 {
		change := batch.changes[i];
		
		mem.copy(&history.flip[0], change.ptr, len(change.bytes));
		mem.copy(change.ptr, &change.bytes[0], len(change.bytes));
		mem.copy(&change.bytes[0], &history.flip[0], len(change.bytes));
	}
	
	container.array_push_back(b, batch);
	return true;
}

// length of units in item 
item_len :: proc(a: ^History, redo: bool) -> int {
	array := redo ? &a.redo : &a.undo;
	return array.len;
}

// byte site of units in item
item_size :: proc(a: ^History, redo: bool) -> (result: int) {
	array := redo ? &a.redo : &a.undo;
	
	for i in 0..<array.len {
		item := container.array_get_ptr(array^, i); 
		for change in item.changes {
			result += len(change.bytes);
		}
	}
	
	return;
}

// tests

_test_simple :: proc() {
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
}

_test_ptrs :: proc() {
	history: History;
	init(&history);
	defer destroy(&history);
	
	b: int = 1;
	c: int = 2;
	d: ^int = &b;
	push(&history, &d);
	push(&history, &d);
	fmt.println("--- TEST POINTERS ---");
	fmt.println("START:", d, d^);
	d = &c;
	commit(&history, "A");
	
	fmt.println("CHANGE:", d, d^);
	fmt.println("UNDO:", undo(&history), d, d^);
	fmt.println("REDO:", redo(&history), d, d^);
	fmt.println("REDO:", redo(&history), d, d^);
}

_test_slice :: proc() {
	history: History;
	init(&history);
	defer destroy(&history);
	
	bytes := []u8 { 0, 1, 3 };
	push_slice(&history, bytes);
	bytes[0] = 1;
	bytes[2] = 4;
	commit(&history, "A");
	
	fmt.println("--- TEST COMPLEX ---");
	fmt.println("START", bytes);
	fmt.println(undo(&history), bytes);
	fmt.println(redo(&history), bytes);
	fmt.println(redo(&history), bytes);
}
