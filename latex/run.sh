#!/bin/bash
set -e

cd "$(dirname "$0")"

pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex

rm -f main.aux main.bbl main.blg main.log main.out main.toc main.lof main.lot main.idx main.ilg main.ind main.bcf main.run.xml

echo "Done: main.pdf"
