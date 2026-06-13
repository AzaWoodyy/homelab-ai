import type { ButtonHTMLAttributes, ReactNode } from "react";

type ButtonTone = "primary" | "soft" | "ghost" | "danger";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  tone?: ButtonTone;
  icon?: ReactNode;
  block?: boolean;
};

export function Button({ tone = "ghost", icon, block = false, className = "", children, ...props }: ButtonProps) {
  return (
    <button className={`button button-${tone}${block ? " button-block" : ""} ${className}`.trim()} {...props}>
      {icon}
      {children}
    </button>
  );
}
