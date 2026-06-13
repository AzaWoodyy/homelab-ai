import type { InputHTMLAttributes, ReactNode, TextareaHTMLAttributes } from "react";

type FieldProps = {
  label: string;
  error?: string;
  children: ReactNode;
};

export function Field({ label, error, children }: FieldProps) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      <span className="field-error" aria-live="polite">
        {error ?? ""}
      </span>
    </label>
  );
}

export function TextInput(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input className="input" type="text" {...props} />;
}

export function SecretInput(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input className="input" type="password" {...props} />;
}

export function TextArea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className="textarea" spellCheck={false} {...props} />;
}
