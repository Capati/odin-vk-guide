package main

// Core
import "core:container/queue"

Deletion_Queue :: queue.Queue(proc())

deletion_queue_push_proc :: proc(d: ^Deletion_Queue, p: proc()) {
	queue.push_front(d, p)
}

deletion_queue_flush :: proc(d: ^Deletion_Queue) {
	for i in 0 ..< d.len {
		f := queue.get(d, i)
		if f != nil do f()
	}
	queue.clear(d)
}
