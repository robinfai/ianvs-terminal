#include <security/pam_appl.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>
#include <stdlib.h>
#include <string.h>

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc,
                                   const char **argv) {
  (void)flags;
  (void)argc;
  (void)argv;
  char *response = NULL;
  int status = pam_prompt(pamh, PAM_PROMPT_ECHO_OFF, &response,
                          "Fixture password: ");
  if (status != PAM_SUCCESS || response == NULL ||
      strcmp(response, "ianvs-e2e-password") != 0) {
    free(response);
    return PAM_AUTH_ERR;
  }
  free(response);
  response = NULL;

  status = pam_prompt(pamh, PAM_PROMPT_ECHO_OFF, &response,
                      "One-time password: ");
  if (status != PAM_SUCCESS || response == NULL ||
      strcmp(response, "654321") != 0) {
    free(response);
    return PAM_AUTH_ERR;
  }
  free(response);
  return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc,
                              const char **argv) {
  (void)pamh;
  (void)flags;
  (void)argc;
  (void)argv;
  return PAM_SUCCESS;
}
