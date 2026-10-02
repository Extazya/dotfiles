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
autocmd VimEnter * NERDTree | wincmd p

" fzf
nnoremap <C-p> :Files<CR>
nnoremap <C-f> :Rg<CR>

" LSP (clangd): completion, go to definition, errors as you type.
" clangd only analyzes the code; compiling stays with gcc. For a project with
" a Makefile, run `bear -- make` once so clangd knows the include paths.
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
