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
} & ({
	type: "copy"
	target!: #file_string
	source!: #file_string
	...
} | {
	type: "symlink"
	source!: _
	...
} | {
	type: "delete" | "directory" | "modify"
	...
})

{
	version: 1
	files: [...#HjemFile]
}
