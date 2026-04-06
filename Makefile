fasm = fasm
src = main.asm
out = 0fetch

inc =            \
	header.inc   \
	procs.inc    \
	syscalls.inc \

version = "0.0.1"

.PHONY: all build clean run

all:
	$(error )

build: $(out)

release: $(out)

$(out): $(src) $(inc) Makefile
	$(info --- build ---)
	$(fasm) -d VERSION='$(version)' -d LATEST_COMMIT=\'$(shell git rev-parse --short HEAD)\' $(src) $(out)
	chmod +x $(out)

run: build
	$(info --- run ---)
	./$(out)

clean:
	rm -f ./$(out)
