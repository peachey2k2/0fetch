<!-- markdownlint-disable MD013 MD033 MD041 -->

<div id="doc-begin" align="center">
  <h1 id="header">0fetch</h1>
  <p>tiny fetch tool written in x86 assembly</p>
    <img width="80%" alt="image" src="https://github.com/user-attachments/assets/9dbb8f51-fc92-4ca3-8179-bf322dab8184" />
  <br/>
  <br/>
</div>

yea yea whatever, here are some bullet points:

- fast (duh)
- very small executable (less than 4KiB)
- no libc or any libraries
- 100% staticly linked
- no heap allocations
- nice cozy display
- fast as fuck
- very cool braille logo (it's kinda tuff)
- did i mention fast

## Okay but why?
Aside from it being conceptually cool, I mainly made this just to fuck with [@NotAShelf](https://github.com/NotAShelf) and [@amaanq](https://github.com/amaanq).

Basically raf ([@NotAShelf](https://github.com/NotAShelf)) made his own fetcher ([microfetch](https://github.com/NotAShelf/microfetch)) and claims it's very small and fast. I initially started this as a rewrite of microfetch, but later on I changed a couple other things to my liking.

Also I like code golfing.

## How do I install it???
1. clone the repo
2. run `make build` (you'll need [fasm](https://flatassembler.net/))
3. add it to your $PATH if you wanna

## But the benchmarks?????
<img width="80%" alt="image" src="https://github.com/user-attachments/assets/aa1665af-3ebd-49ea-af4e-e2f187a727a9" />

#mogged #packwatch #ripbozo #RolledAndSmoked etc.

Want more stupid fancy tables? Go stare at [microfetch's benchmarks](https://github.com/NotAShelf/microfetch?tab=readme-ov-file#benchmarks).

## But portability?????????????
<img width="80%" alt="image" src="https://github.com/user-attachments/assets/e3377a5b-72de-4193-bf93-3b2ca0907b99" />


## How do I customize
You don't. Just go use [fastfetch](https://github.com/fastfetch-cli/fastfetch) like a normal person if you want that.

Or alternatively, write your own. Trust me it's not that hard.
