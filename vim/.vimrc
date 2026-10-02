call plug#begin('~/.vim/plugged')

Plug 'preservim/nerdtree'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-surround'
Plug 'morhetz/gruvbox'

call plug#end()

set nocompatible
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
