#HjemFile: {
	type: "symlink"
	source: string
	target: string
	clobber: bool
	executable: bool
}

#HjemManifest: {
	version: 1
	files: [...#HjemFile]
}
