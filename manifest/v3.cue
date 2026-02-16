#path_string: string & =~ "^/"
#file_string: #path_string & =~ "[^/]$"
#octal_string: string & =~ "^[0-7]{3,4}$"

#HjemFile: {
	type!: string
	source?: #path_string
	target!: #path_string
	clobber?: bool
	permissions?: #octal_string
	uid?: int & >=0
	gid?: int & >=0
	deactivate?: bool
	ignore_modification?: bool
} & ({
	type: "copy"
	// "copy" only works with individual files
	source!: #file_string
	target!: #file_string
	...
} | {
	type: "symlink"
	source!: _
	// disallow inapplicable fields
	ignore_modification?: _|_
	permissions?: _|_
	uid?: _|_
	gid?: _|_
	...
} | {
	type: "delete" | "directory" | "modify"
	ignore_modification?: _|_
	source?: _|_
	...
})

close({
	version: 3
	files: [...#HjemFile]
})
