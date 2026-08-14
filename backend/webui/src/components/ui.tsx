import {
  useEffect,
  useId,
  useRef,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react'

export function Spinner({ label = 'Loading' }: { label?: string }) {
  return (
    <span className="spinner" role="status" aria-label={label}>
      <span className="spinner__ring" aria-hidden="true" />
    </span>
  )
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  busy?: boolean
  icon?: ReactNode
}

export function Button({
  variant = 'secondary',
  busy = false,
  icon,
  children,
  className = '',
  disabled,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={`button button--${variant} ${className}`}
      disabled={disabled || busy}
      aria-busy={busy || undefined}
      {...rest}
    >
      {busy ? <Spinner label="Working" /> : icon}
      {children}
    </button>
  )
}

interface FieldBaseProps {
  label: string
  hint?: string
  error?: string
  required?: boolean
  children: (id: string, describedBy: string | undefined) => ReactNode
}

function FieldBase({ label, hint, error, required, children }: FieldBaseProps) {
  const id = useId()
  const hintId = hint ? `${id}-hint` : undefined
  const errorId = error ? `${id}-error` : undefined
  const describedBy = [hintId, errorId].filter(Boolean).join(' ') || undefined
  return (
    <div className={`field ${error ? 'field--error' : ''}`}>
      <label className="field__label" htmlFor={id}>
        {label}
        {required ? (
          <>
            {' '}
            <span aria-hidden="true" className="field__required">
              *
            </span>
            <span className="sr-only">(required)</span>
          </>
        ) : null}
      </label>
      {children(id, describedBy)}
      {hint && !error ? (
        <p id={hintId} className="field__hint">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} className="field__error" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  )
}

type TextFieldProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'children'> & {
  label: string
  hint?: string
  error?: string
}

export function TextField({ label, hint, error, required, ...inputProps }: TextFieldProps) {
  return (
    <FieldBase label={label} hint={hint} error={error} required={required}>
      {(id, describedBy) => (
        <input
          id={id}
          className="input"
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          required={required}
          {...inputProps}
        />
      )}
    </FieldBase>
  )
}

type TextAreaFieldProps = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'children'> & {
  label: string
  hint?: string
  error?: string
  mono?: boolean
}

export function TextAreaField({
  label,
  hint,
  error,
  required,
  mono = false,
  ...textareaProps
}: TextAreaFieldProps) {
  return (
    <FieldBase label={label} hint={hint} error={error} required={required}>
      {(id, describedBy) => (
        <textarea
          id={id}
          className={`input ${mono ? 'input--mono' : ''}`}
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          required={required}
          {...textareaProps}
        />
      )}
    </FieldBase>
  )
}

type SelectFieldProps = Omit<SelectHTMLAttributes<HTMLSelectElement>, 'children'> & {
  label: string
  hint?: string
  error?: string
  children: ReactNode
}

export function SelectField({ label, hint, error, required, children, ...selectProps }: SelectFieldProps) {
  return (
    <FieldBase label={label} hint={hint} error={error} required={required}>
      {(id, describedBy) => (
        <select
          id={id}
          className="input"
          aria-invalid={error ? true : undefined}
          aria-describedby={describedBy}
          required={required}
          {...selectProps}
        >
          {children}
        </select>
      )}
    </FieldBase>
  )
}

export function CheckboxField({
  label,
  hint,
  checked,
  onChange,
  disabled,
}: {
  label: string
  hint?: string
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
}) {
  const id = useId()
  return (
    <div className="checkbox-field">
      <input
        id={id}
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
      />
      <label htmlFor={id}>
        <span>{label}</span>
        {hint ? <span className="checkbox-field__hint">{hint}</span> : null}
      </label>
    </div>
  )
}

export function Badge({
  tone = 'neutral',
  children,
}: {
  tone?: 'neutral' | 'success' | 'warning' | 'error' | 'info'
  children: ReactNode
}) {
  return <span className={`badge badge--${tone}`}>{children}</span>
}

export function Card({
  title,
  actions,
  children,
  className = '',
}: {
  title?: ReactNode
  actions?: ReactNode
  children: ReactNode
  className?: string
}) {
  return (
    <section className={`card ${className}`}>
      {title || actions ? (
        <header className="card__header">
          {title ? <h2 className="card__title">{title}</h2> : <span />}
          {actions ? <div className="card__actions">{actions}</div> : null}
        </header>
      ) : null}
      <div className="card__body">{children}</div>
    </section>
  )
}

export function Notice({
  tone = 'info',
  children,
  role,
}: {
  tone?: 'info' | 'success' | 'warning' | 'error'
  children: ReactNode
  role?: 'status' | 'alert'
}) {
  return (
    <div className={`notice notice--${tone}`} role={role}>
      {children}
    </div>
  )
}

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string
  description?: string
  action?: ReactNode
}) {
  return (
    <div className="empty-state">
      <p className="empty-state__title">{title}</p>
      {description ? <p className="empty-state__description">{description}</p> : null}
      {action ? <div className="empty-state__action">{action}</div> : null}
    </div>
  )
}

const FOCUSABLE_SELECTOR =
  'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'

export function Dialog({
  open,
  title,
  onClose,
  children,
  footer,
}: {
  open: boolean
  title: string
  onClose: () => void
  children: ReactNode
  footer?: ReactNode
}) {
  const dialogRef = useRef<HTMLDivElement>(null)
  const previouslyFocused = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (!open) return
    previouslyFocused.current = document.activeElement as HTMLElement | null
    const dialog = dialogRef.current
    const first = dialog?.querySelector<HTMLElement>(FOCUSABLE_SELECTOR)
    first?.focus()

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault()
        onClose()
        return
      }
      if (event.key !== 'Tab' || !dialog) return
      const focusable = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
      if (focusable.length === 0) return
      const firstEl = focusable[0]
      const lastEl = focusable[focusable.length - 1]
      if (event.shiftKey && document.activeElement === firstEl) {
        event.preventDefault()
        lastEl.focus()
      } else if (!event.shiftKey && document.activeElement === lastEl) {
        event.preventDefault()
        firstEl.focus()
      }
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      previouslyFocused.current?.focus()
    }
  }, [open, onClose])

  if (!open) return null

  return (
    <div className="dialog-backdrop" onMouseDown={onClose}>
      <div
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        ref={dialogRef}
        onMouseDown={(event) => event.stopPropagation()}
      >
        <header className="dialog__header">
          <h2 className="dialog__title">{title}</h2>
          <button type="button" className="icon-button" aria-label={`Close ${title}`} onClick={onClose}>
            ✕
          </button>
        </header>
        <div className="dialog__body">{children}</div>
        {footer ? <footer className="dialog__footer">{footer}</footer> : null}
      </div>
    </div>
  )
}
