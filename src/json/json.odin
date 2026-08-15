package json

parse :: proc(file_path: string) {
	parser: Parser
	if !parser_init(&parser, file_path) {
		return
	}
	defer parser_destroy(&parser)

	parser_parse(&parser)
}
