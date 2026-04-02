fasm = fasm

src = main.asm

inc = macros.inc

out = 0fetch

.PHONY: all build release run

all:
	$(error )

build: $(src) $(inc) Makefile
	$(info --- build ---)
	$(fasm) $(src) $(out)

run: build
	$(info --- run ---)
	./$(out)

clean:
	rm $(out)
