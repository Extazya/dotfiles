call plug#begin('~/.vim/plugged')

Plug 'preservim/nerdtree'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-surround'
Plug 'morhetz/gruvbox'
Plug 'yegappan/lsp'
Plug 'LunarWatcher/auto-pairs'

call plug#end()

set nocompatible
set encoding=utf-8
set number relativenumber
set tabstop=4 shiftwidth=4 noexpandtab
set autoindent smartindent
set hlsearch incsearch ignorecase smartcase
set scrolloff=8
set nowrap
set backspace=indent,eol,start
set wildmenu wildmode=longest:full,full
set laststatus=2
set ruler
set showcmd
set cursorline
" 42 norm: 80 columns max; tabs drawn as indent guides, trailing spaces as dots
set colorcolumn=81
set list listchars=tab:│\ ,trail:·,nbsp:␣
" Always reserve the error sign column so text doesn't shift when one appears
set signcolumn=yes
syntax on
filetype plugin indent on

colorscheme gruvbox
set background=dark

" NERDTree
nnoremap <C-n> :NERDTreeToggle<CR>
" Open the tree only when browsing: `vim` alone or `vim <dir>`, not for files
" (so not for `git commit` either)
autocmd StdinReadPre * let s:std_in = 1
autocmd VimEnter * if !exists('s:std_in') && argc() == 0 | NERDTree | wincmd p | endif
autocmd VimEnter * if !exists('s:std_in') && argc() == 1 && isdirectory(argv()[0])
	\ | execute 'NERDTree' argv()[0] | wincmd p | enew | execute 'cd' argv()[0] | endif

" fzf
nnoremap <C-p> :Files<CR>
nnoremap <C-f> :Rg<CR>

" LSP (clangd): completion, go to definition, errors as you type.
" clangd only analyzes the code; compiling stays with gcc.
autocmd User LspSetup call LspOptionsSet(#{
	\ noNewlineInCompletion: v:true,
	\ showDiagWithVirtualText: v:true,
	\ })
autocmd User LspSetup call LspAddServer([#{
	\ name: 'clangd',
	\ filetype: ['c', 'cpp'],
	\ path: 'clangd',
	\ args: ['--background-index', '--header-insertion=never'],
	\ }])
autocmd User LspAttached nnoremap <buffer> <silent> gd <cmd>LspGotoDefinition<CR>
autocmd User LspAttached nnoremap <buffer> <silent> gr <cmd>LspShowReferences<CR>
autocmd User LspAttached nnoremap <buffer> <silent> K  <cmd>LspHover<CR>
autocmd User LspAttached nnoremap <buffer> <silent> ]d <cmd>LspDiag next<CR>
autocmd User LspAttached nnoremap <buffer> <silent> [d <cmd>LspDiag prev<CR>
autocmd User LspAttached nnoremap <buffer> <silent> gl <cmd>LspDiag current<CR>

" clangd only knows a Makefile's flags (-I, -D...) through compile_commands.json.
" bear records it in the background (make -Bk: rebuild everything, keep going
" past errors) when a C file is opened in a Makefile project that has none, and
" again whenever the Makefile is saved. A compile_flags.txt turns this off.
let s:bear_jobs = {}

" Closest directory from dir up to $HOME containing one of names, or ''
function! s:FindUp(dir, names) abort
	let d = a:dir
	while 1
		for n in a:names
			if filereadable(d . '/' . n) | return d | endif
		endfor
		let up = fnamemodify(d, ':h')
		if up ==# d || d ==# $HOME | return '' | endif
		let d = up
	endwhile
endfunction

function! s:Bear(file, refresh) abort
	if empty(a:file) || !executable('bear') | return | endif
	let dir = fnamemodify(a:file, ':h')
	let root = s:FindUp(dir, ['Makefile', 'makefile'])
	if empty(root) || has_key(s:bear_jobs, root)
		\ || !empty(s:FindUp(dir, ['compile_flags.txt']))
		\ || (!a:refresh && !empty(s:FindUp(dir, ['compile_commands.json'])))
		return
	endif
	let s:bear_jobs[root] = job_start(['bear', '--', 'make', '-Bk'], #{
		\ cwd: root, in_io: 'null', out_io: 'null', err_io: 'null',
		\ exit_cb: function('s:BearDone', [root])})
endfunction

" Restart clangd so open buffers pick up the new flags. The restart applies to
" the current buffer's filetype: wait for a C buffer if we're elsewhere.
function! s:BearDone(root, job, status) abort
	call remove(s:bear_jobs, a:root)
	augroup bear_restart
		autocmd!
		if &filetype =~# '^c\(pp\)\=$'
			silent! LspServer restart
		else
			autocmd BufEnter *.c,*.h ++once silent! LspServer restart
		endif
	augroup END
endfunction

autocmd FileType c,cpp call s:Bear(expand('<afile>:p'), 0)
autocmd BufWritePost Makefile,makefile call s:Bear(expand('<afile>:p'), 1)

" Auto-close (), [], {}, quotes. Backspace inside an empty pair deletes both.
" Enter is mapped once here: accept the completion menu if it's open,
" otherwise new line (and open the block when between {}).
let g:AutoPairsMapBS = 1
let g:AutoPairsMapCR = 0
imap <expr> <CR> pumvisible() ? "\<C-y>" : "\<CR>\<Plug>AutoPairsReturn"

" :make without a Makefile compiles the current file alone with the 42 flags
autocmd FileType c if !filereadable('Makefile') && !filereadable('makefile')
	\ | setlocal makeprg=cc\ -Wall\ -Wextra\ -Werror\ %\ -o\ %<
	\ | endif

" New Makefiles start from the all/clean/fclean/re template
autocmd BufNewFile Makefile,makefile 0read ~/.vim/templates/Makefile | $delete _ | 1
