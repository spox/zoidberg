# v0.3.0
* Initial internal refactor utilizing ruby-concurrent

# v0.2.2
* Remove async threads once they have reached completion
* Attempt to locate free worker in pool for async, random pick if none

# v0.2.0
* Update termination behaviors to ensure expected results
* Provide and use flag for system shutdown to disable supervision
* Proper termination behavior when not supervised
* Prevent pool from dying on worker exceptions

# v0.1.12
* Move event signal to abstract proxy
* Update timeout library usage
* Remove defer usage fetching worker within pool
* Clean locking usage to prevent miscounts
* Fix async style locking to ensure expected behavior

# v0.1.10
* Handle unexpected errors from asyncs while supervised
* Pool releases lock once worker has been aquired
* Provide better string generation of abort exceptions

# v0.1.8
* Fix to properly remove canceled actions

# v0.1.6
* Add Zoidberg::Lazy
* Explicitly state what shells are used internally
* DRY raw instance wrapping
* Flag signal context and disable any locking

# v0.1.4
* Timer updates and fix spec

# v0.1.2
* Use select + pipe for timer interactions

# v0.1.0
* Initial release
