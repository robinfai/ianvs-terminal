const DEVICE_KEY = 'ianvs.device-id'

// Per browser profile, shared by tabs. No hardware fingerprint or login secret.
export function deviceIdentity(): string {
  let id = localStorage.getItem(DEVICE_KEY)
  if (!id) {
    id = crypto.randomUUID()
    localStorage.setItem(DEVICE_KEY, id)
  }
  return id
}
