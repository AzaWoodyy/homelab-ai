import * as AlertDialog from "@radix-ui/react-alert-dialog";
import type { ReactNode } from "react";
import { Button } from "./Button";

type DangerDialogProps = {
  title: string;
  description: string;
  confirmLabel: string;
  children: ReactNode;
  onConfirm: () => void;
  disabled?: boolean;
};

export function DangerDialog({ title, description, confirmLabel, children, onConfirm, disabled }: DangerDialogProps) {
  return (
    <AlertDialog.Root>
      <AlertDialog.Trigger asChild disabled={disabled}>
        {children}
      </AlertDialog.Trigger>
      <AlertDialog.Portal>
        <AlertDialog.Overlay className="dialog-overlay" />
        <AlertDialog.Content className="dialog-content">
          <AlertDialog.Title className="dialog-title">{title}</AlertDialog.Title>
          <AlertDialog.Description className="dialog-description">{description}</AlertDialog.Description>
          <div className="dialog-actions">
            <AlertDialog.Cancel asChild>
              <Button type="button">Cancel</Button>
            </AlertDialog.Cancel>
            <AlertDialog.Action asChild>
              <Button type="button" tone="danger" onClick={onConfirm}>
                {confirmLabel}
              </Button>
            </AlertDialog.Action>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Portal>
    </AlertDialog.Root>
  );
}
