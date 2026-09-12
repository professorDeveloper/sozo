package com.soplay.sozo

/**
 * Turns a throwable from an extension into the one line the app can show.
 *
 * ## Why the message alone is not enough
 *
 * Extensions are entered by reflection, and reflection wraps: constructing a
 * source that throws produces an `InvocationTargetException` whose own message
 * is `null` and whose cause carries the real failure. Reporting `t.message`
 * gave the user exactly what it says on the tin —
 *
 *     Aniyomi: instantiate …anikage.Anikage: InvocationTargetException: null
 *
 * — a sentence with the plumbing in it and the reason missing. The same shape
 * appears wherever a `Callable`, a coroutine or a `ClassLoader` sits between us
 * and the code that actually failed.
 *
 * So: walk to the root, and name the root. The wrapper is still in logcat,
 * where the whole chain belongs.
 */
object ExtensionFailure {

    /** The deepest cause, which is the one that actually went wrong. */
    fun rootOf(t: Throwable): Throwable {
        var root = t
        val seen = HashSet<Throwable>()
        while (true) {
            val cause = root.cause ?: return root
            // A cycle is rare and always a bug in someone's exception plumbing,
            // but walking one forever would hang the thread that is trying to
            // report an error.
            if (!seen.add(root) || cause === root) return root
            root = cause
        }
    }

    /**
     * `Type: message`, or just `Type` when there is nothing useful to add.
     *
     * The type is always there because it is often the whole answer:
     * `NoSuchMethodError` says the extension was built against a newer library
     * than we bundle, and that is actionable in a way "null" is not.
     */
    fun describe(t: Throwable): String {
        val root = rootOf(t)
        val message = root.message?.trim().orEmpty()
        val type = root.javaClass.simpleName.ifEmpty { root.javaClass.name }
        return if (message.isEmpty() || message == "null") type else "$type: $message"
    }
}
