#################################################
#
# central macro to register an examples in cmake
#
# Examples can be globally executed by 'make run_examples'
#
# 1) Simple use:
# Pass the name of the source.cc file as the first
# argument, without the ".cc" extention.
#
# Example: CORSIKA_REGISTER_EXAMPLE (doSomething)
#
# The TARGET doSomething must already exists,
#    i.e. typically via add_executable (doSomething src.cc).
#
# Example: CORSIKA_ADD_EXAMPLE (example_one
#              RUN_OPTION "extra command line options"
#              )
#
# In all cases, you can further customize the target with
# target_link_libraries (example_one ...) and so on.
#
function (CORSIKA_REGISTER_EXAMPLE)
  cmake_parse_arguments (PARSE_ARGV 1 C8_EXAMPLE "" "" "RUN_OPTIONS")
  set (name ${ARGV0})

  if (NOT C8_EXAMPLE_RUN_OPTIONS)
    set (run_options "")
  else ()
    set (run_options ${C8_EXAMPLE_RUN_OPTIONS})
  endif ()

  target_compile_options (${name} PRIVATE -g) # do not skip asserts
  file (MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/example_outputs/)
  if (TARGET run_examples)
  else ()
    add_custom_target (run_examples)
  endif ()
  add_dependencies (run_examples ${name})
  # just run the command as-is
  set (CMD ${CMAKE_CURRENT_BINARY_DIR}/bin/${name} ${run_options})
  add_custom_command (TARGET run_examples
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E echo ""
    COMMAND ${CMAKE_COMMAND} -E echo "**************************************"
    COMMAND ${CMAKE_COMMAND} -E echo "*****   example: ${name} " ${run_options} VERBATIM
    COMMAND ${CMAKE_COMMAND} -E echo "*****   running command: " ${CMD} VERBATIM
    COMMAND ${CMD} VERBATIM
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/example_outputs)
  install (TARGETS ${name} DESTINATION share/examples)
endfunction (CORSIKA_REGISTER_EXAMPLE)
