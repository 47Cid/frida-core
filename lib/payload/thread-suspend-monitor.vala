namespace Frida {
#if DARWIN
	public class ThreadSuspendMonitor : Object {
		public weak ThreadSuspendScriptRunner runner {
			get;
			construct;
		}

		private TaskThreadsFunc task_threads;
		private ThreadSuspendFunc thread_resume;
		private ThreadResumeFunc thread_suspend;

		private const string LIBSYSTEM_KERNEL = "/usr/lib/system/libsystem_kernel.dylib";

		[CCode (has_target = false)]
		private delegate int TaskThreadsFunc (uint task_id, uint ** threads, uint * count);
		[CCode (has_target = false)]
		private delegate int ThreadSuspendFunc (uint thread_id);
		[CCode (has_target = false)]
		private delegate int ThreadResumeFunc (uint thread_id);

		public ThreadSuspendMonitor (ThreadSuspendScriptRunner runner) {
			Object (runner: runner);
		}

		construct {
			var interceptor = Gum.Interceptor.obtain ();

			task_threads = (ThreadResumeFunc) Gum.Module.find_export_by_name (LIBSYSTEM_KERNEL, "task_threads");
			thread_suspend = (ThreadSuspendFunc) Gum.Module.find_export_by_name (LIBSYSTEM_KERNEL, "thread_suspend");
			thread_resume = (ThreadResumeFunc) Gum.Module.find_export_by_name (LIBSYSTEM_KERNEL, "thread_resume");

			interceptor.replace_function ((void *) task_threads, (void *) replacement_task_threads, this);
			interceptor.replace_function ((void *) thread_suspend, (void *) replacement_thread_suspend, this);
			interceptor.replace_function ((void *) thread_resume, (void *) replacement_thread_resume, this);
		}

		public override void dispose () {
			var interceptor = Gum.Interceptor.obtain ();

			interceptor.revert_function ((void *) thread_suspend);

			base.dispose ();
		}

		private static int replacement_task_threads (uint task_id, uint ** threads, uint * count) {
			unowned Gum.InvocationContext context = Gum.Interceptor.get_current_invocation ();
			unowned ThreadSuspendMonitor monitor = (ThreadSuspendMonitor) context.get_replacement_function_data ();

			return monitor.handle_task_threads (task_id, threads, count);
		}

		private int handle_task_threads (uint task_id, uint ** threads, uint * count) {
			int result = task_threads (task_id, threads, count);

			_remove_cloaked_threads (task_id, threads, count);

			return result;
		}

		public extern static void _remove_cloaked_threads (uint task_id, uint ** threads, uint * count);

		private static int replacement_thread_suspend (uint thread_id) {
			unowned Gum.InvocationContext context = Gum.Interceptor.get_current_invocation ();
			unowned ThreadSuspendMonitor monitor = (ThreadSuspendMonitor) context.get_replacement_function_data ();

			return monitor.handle_thread_suspend (thread_id);
		}

		private int handle_thread_suspend (uint thread_id) {
			if (Gum.Cloak.has_thread (thread_id))
				return 0;

			var script_backend = runner.get_current_script_backend ();
			uint caller_thread_id = (uint) Gum.Process.get_current_thread_id ();
			if (script_backend == null || thread_id == caller_thread_id)
				return thread_suspend (thread_id);

			int result = 0;

			while (true) {
				script_backend.with_lock_held (() => {
					result = thread_suspend (thread_id);
				});

				if (result != 0 || !script_backend.is_locked ())
					break;

				if (thread_resume (thread_id) != 0)
					break;
			}

			return result;
		}

		private static int replacement_thread_resume (uint thread_id) {
			unowned Gum.InvocationContext context = Gum.Interceptor.get_current_invocation ();
			unowned ThreadSuspendMonitor monitor = (ThreadSuspendMonitor) context.get_replacement_function_data ();

			return monitor.handle_thread_resume (thread_id);
		}

		private int handle_thread_resume (uint thread_id) {
			if (Gum.Cloak.has_thread (thread_id))
				return 0;

			return thread_resume (thread_id);
		}
	}
#else
	public class ThreadSuspendMonitor : Object {
		public weak ThreadSuspendScriptRunner runner {
			get;
			construct;
		}

		public ThreadSuspendMonitor (ThreadSuspendScriptRunner runner) {
			Object (runner: runner);
		}
	}
#endif

	public interface ThreadSuspendScriptRunner : Object {
		public abstract Gum.ScriptBackend? get_current_script_backend ();
	}
}