# Locks

A pre-flight lock guard refuses to proceed when a live foreign session already holds the
intent lock; this is the sole mechanism that keeps two sessions from writing the same intent
at once.
