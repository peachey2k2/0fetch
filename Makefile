fasm = fasm

src = main.asm

inc = macros.inc

out = 0fetch

.PHONY: all build clean run

all:
	$(error )

build: $(out)

$(out): $(src) $(inc) Makefile
	$(info --- build ---)
	$(fasm) $(src) $(out)

run: build
	$(info --- run ---)
	./$(out)

clean:
	rm ./$(out)
