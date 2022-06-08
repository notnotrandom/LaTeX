#! /bin/bash

# See the end of file for explanatory comments.

##### VARIABLES THAT THE USER CAN SET #####
# To disable building bibliography, set this to false.
do_bib="true"

# If set to "false", suppresses the output of bibliography building commands.
# Set to any other value -- e.g. "true" -- to show said commands' output.
verbose="false"
###########################################

name="article"

# The final name of the .pdf file (without extension). Defaults to original
# name with ".FINAL" appended. In my setup, works "out of the box" with spaces,
# foreign chars, ...
finalname="${name}.FINAL"

# Name of the .bib file (sans extension).
sourcesname="sources"

# Build dir.
build_dir="build"

texcmd="xelatex"
texcmdopts="-halt-on-error --interaction=batchmode --shell-escape --synctex=1"
debug_texcmdopts="--interaction=errorstopmode --shell-escape --synctex=1 --output-directory=${build_dir}"
bibcmd="bibulous"
indexcmd="makeindex"

# Colours.
SUCCESS='\033[0;34m'
ERROR='\033[0;31m'
NC='\033[0m' # No Color

# A big LaTeX compile: compile once (and build index, if it is set), then compile
# bib (if it is set), then compile three more times (usually two are enough, but in
# some thorny cases three are required, so...). If using bib is not set, just
# compile three times.
function big_build() {
  read -n1 -s -r -p $'Press <Enter> to continue (Ctrl-C to cancel)...' key
  if [ "$key" = '' ]; then
    echo
  else
    echo
    return 1
  fi

  # First, run compile(). 
  echo "$0: Compile #1..."
  compile "$name" "$build_dir"
  # If the compile failed, notify the user and quit.
  if [[ $? -ne 0 ]]; then
    echo -e "Compilation of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  fi

  # If the previous compile succeeded, and we are not building bibliography,
  # then just compile twice more and exit.
  if [[ "$do_bib" == "false" ]] ; then
    echo "$0: The \$do_bib var is set to false, so I am skipping the bibliography part."
    echo "$0: I will just run compile() twice more."
    echo "$0: Compile #2 and #3..."
    compile "$name" "$build_dir" && compile "$name" "$build_dir"
    # If one of the compile runs failed, notify the user and quit.
    if [[ $? -ne 0 ]]; then
      echo -e "(2nd or 3rd) compile run of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
      return 1
    fi

  # Else, if $do_bib is true, and there are uncommented \cite or \nocite
  # commands, then build the bibliography. The reason for *three* compiles,
  # instead of the usual two, is that an extra compile is required for
  # backreferences in bib entries to be constructed (e.g. "Cited in page ...").
  else
    local have_cite_entries=$(grep --extended-regexp --recursive '^[^%]*\\(no)?cite' --include=*.tex)
    # No \cite or \nocite entries have been found.
    if [[ -z "$have_cite_entries" ]]; then
      echo "$0: The $do_bib var is set to true, but no \\cite entries found.
      So I will just do two more compile runs..."
      echo "$0: Compile #2 and #3..."
      compile "$name" "$build_dir" && compile "$name" "$build_dir"
      # If one of the compile runs failed, notify the user and quit.
      if [[ $? -ne 0 ]]; then
        echo -e "(2nd or 3rd) compile run of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
        return 1
      fi
      # Some \cite or \nocite entries have been found -- hence more three compiles.
    else
      if [[ "$verbose" == "false" ]]; then
        cd "${build_dir}"
        echo "$0: Bibliography build #1..."
        ${bibcmd} "${name}.aux" > /dev/null
      else
        cd "${build_dir}" && pwd
        ${bibcmd} "${name}.aux"
      fi

      if [[ $? -eq 0 ]]; then
        cd ..
        echo "$0: Compile #2 and #3..."
        compile "$name" "$build_dir" && \
        compile "$name" "$build_dir"

# Now check for undefined references.
        undef_refs=$(sed -En "s/^.+ Citation \`(.+)' on page .+ undefined.*$/\1/p" "${build_dir}/${name}.log")

        if [[ -n "$undef_refs" ]]; then
# If undefined citations are found after the first two compiles after having
# built the bibliography, then we need to re-build the bibliography, and do two
# more compiles after that. But first warn the user.
          echo "Found undefined citations: $undef_refs"
          echo "Re-building bibliography, and doing TWO more further compilations."

          if [[ "$verbose" == "false" ]]; then
            cd "${build_dir}"
            echo "$0: Bibliography build #2..."
            ${bibcmd} "${name}.aux" > /dev/null
          else
            cd "${build_dir}" && pwd
            ${bibcmd} "${name}.aux"
          fi
          if [[ $? -eq 0 ]]; then
            cd ..
            echo "$0: Compile #4 and #5..."
            compile "$name" "$build_dir" && \
            compile "$name" "$build_dir"
            if [[ $? -ne 0 ]]; then
              echo -e "Compile of ${name}.tex, after building bibliography (SECOND TIME), was ${ERROR}NOT SUCCESSFUL${NC}!"
              return 1
            fi
          else
            echo -e "Building bibliography (regular copy, SECOND TIME) file was ${ERROR}NOT SUCCESSFUL${NC}!"
            return 1
          fi
        fi
# Whether or not there were undefined references, compile one final time. In
# either case, this will be the third compile run after the latest bibliography
# build.
        echo -n "$0: Compile (final run)... "
        compile "$name" "$build_dir"
# If this last compile failed, notify the user and quit.
        if [[ $? -ne 0 ]]; then
          echo -e "Last compile of ${name}.tex was ${ERROR}NOT SUCCESSFUL${NC}!"
          return 1
        fi
        echo -e "${SUCCESS}Success${NC}."

# If the compiles were successful, but we still have undefined references, then
# just warn the user, and let him deal with it.
        undef_refs=$(sed -En "s/^.+ Citation \`(.+)' on page .+ undefined.*$/\1/p" "${build_dir}/${name}.log")

        if [[ -n "$undef_refs" ]]; then
          echo "There are still undefined citations: $undef_refs!!"
        fi
      else
        echo -e "Building bibliography (first run, regular copy) file was ${ERROR}NOT SUCCESSFUL${NC}!"
        return 1
      fi
    fi
  fi
}

function check_warnings() {
  grep 'LaTeX Warning' "build/${name}.log"
}

function clean() {
  if [[ -d "$build_dir" ]]; then
    echo "Wiping contents of ${build_dir} (except PDF files)"
    cd "${build_dir}" && rm -rf $(ls | grep -v ".pdf") && cd ..
  else
    echo "Creating directory ${build_dir}"
    mkdir $build_dir
  fi

  # Rebuilding structure of build_dirs. Begin with symlinks.
  dir_and_symlinks_rebuild
}

# A normal (single) LaTeX compile.
function compile() {
  ${texcmd} ${texcmdopts} --output-directory="$2" "$1" > /dev/null
  local ret=$?
  return $ret
}

# A normal (single) LaTeX compile.
function debugbuild() {
  ${texcmd} ${debug_texcmdopts} ${name}
  return $?
}

function dir_and_symlinks_rebuild() {
  if [[ ! -d "$build_dir" ]]; then
    echo "$0: Build dir does not exist! Run clean() to fix it."
    return 1
  fi

  rm -f "${name}.pdf"
  rm -f "${name}.synctex.gz"
  rm -f "${build_dir}/${sourcesname}.bib"

  ln -sr "${build_dir}/${name}.pdf" .
  ln -sr "${build_dir}/${name}.synctex.gz" .
  ln -sr ${sourcesname}.bib "${build_dir}"/
}

function final_document() {
  clean
  big_build
  cp "${build_dir}"/"${name}.pdf" "${finalname}.pdf"
}

# Do a normal compile.
function small_build() {
  echo -n "$0: Compiling... "
  compile "$name" "$build_dir" # compile() returns the $? of the LaTeX command. See Note (1).
  if [[ $? -ne 0 ]]; then
    echo -e "Compile of ${name}.tex file was ${ERROR}NOT SUCCESSFUL${NC}!"
    return 1
  else
    echo -e "${SUCCESS}Success${NC}."
  fi
}

#
# *** Main function ***
#
function main() {
# Check that we are in the dir containing the main file.
  if ! [[ -f "${name}.tex" ]]; then
    echo "Could not find main file ${name}.tex. Exiting..."
    exit 1
  fi

  # If no arguments given, do a normal build;
  # - argument is debug: do debug build;
  if [[ $# -eq 0 ]] ; then
    small_build
  elif [[ $# -eq 1 && "$1" == "big" ]] ; then
    big_build
  elif [[ $# -eq 1 && "$1" == "clean" ]] ; then
    clean
  elif [[ $# -eq 1 && "$1" == "debug" ]] ; then
    debugbuild
  elif [[ $# -eq 1 && "$1" == "final" ]] ; then
    final_document
  elif [[ $# -eq 1 && "$1" == "symlinks" ]] ; then
    dir_and_symlinks_rebuild
  elif [[ $# -eq 1 && "$1" == "warnings" ]] ; then
    check_warnings
  else
    echo "Unknown option(s): $@"
    exit 1
  fi
}

main "$@"

###############################################################################
#
# Much like targets in a Makefile, this scripts provides functions to do a
# simple build, a full build, etc, for a LaTeX project.
#
# Three main functions, compile(), small_build(), and big_build():
#
# - compile() just runs the LaTeX compiler on whatever file it is given;
#
# - small_build() runs compile().
#
# - big_build() runs compile() once, then build bibliography etc. (if
# required), and then runs compile() three more times.
#
# Most of the remaining functions revolve around these three, to check for
# errors and give feedback properly, and so on.
#
###############################################################################

###

# Notes:
# - (1) After an unsuccessful compilation, and after fixing the mistake that
#   caused it, a normal compile, in batchmode with halt on errors, will still lead
#   to a natbib error. It goes away after doing another normal compile. But perhaps
#   the best strategy is to do debug mode in case of errors...
