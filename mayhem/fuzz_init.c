/* Constructor for the mined fuzz_msg_parser: before upstream's fix the harness does not set up the
 * core statistics that parse_msg() bumps on every parse error (update_stat(bad_msg_hdr)). */
#include "../core_stats.h"

__attribute__((constructor (101))) void
mayhem_fuzz_init(void)
{
  static stat_val bad_URIs_c;
  static stat_val bad_msg_hdr_c;
  static stat_var _bad_URIs = {.u.val = &bad_URIs_c};
  static stat_var _bad_msg_hdr = {.u.val = &bad_msg_hdr_c};

  bad_URIs = &_bad_URIs;
  bad_msg_hdr = &_bad_msg_hdr;
}
