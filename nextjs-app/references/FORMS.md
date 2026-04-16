# Zod Schemas

Single source of truth for both form validation and API response parsing.

```ts
// schemas/order.ts
import { z } from "zod";

export const orderLineSchema = z.object({
  productId: z.string().uuid(),
  quantity: z.number().int().positive(),
});

export const placeOrderSchema = z.object({
  customerId: z.string().uuid(),
  lines: z.array(orderLineSchema).min(1, "At least one line required"),
});

export const orderSchema = z.object({
  id: z.string().uuid(),
  customerId: z.string().uuid(),
  status: z.enum(["draft", "pending", "confirmed", "cancelled"]),
  lines: z.array(orderLineSchema),
  createdAt: z.string().datetime(),
});

export const ordersSchema = z.array(orderSchema);

export type Order = z.infer<typeof orderSchema>;
export type PlaceOrderPayload = z.infer<typeof placeOrderSchema>;
```

Rules:
- Derive TypeScript types from schemas with `z.infer<>` — never define the
  type separately.
- Use the *same* schema for `react-hook-form` validation and for API response
  parsing.

---

# React Hook Form + Zod

Forms use Client Components with `react-hook-form` and Zod validation.

```tsx
// app/orders/new/page.tsx
"use client";

import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { useRouter } from "next/navigation";
import { placeOrderSchema, type PlaceOrderPayload } from "@/schemas/order";
import { usePlaceOrder } from "@/hooks/use-orders";

export default function NewOrderPage() {
  const router = useRouter();
  const { mutate, isPending, error } = usePlaceOrder();

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<PlaceOrderPayload>({
    resolver: zodResolver(placeOrderSchema),
  });

  const onSubmit = (data: PlaceOrderPayload) =>
    mutate(data, {
      onSuccess: (order) => router.push(`/orders/${order.id}`),
    });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register("customerId")} placeholder="Customer ID" />
      {errors.customerId && <p>{errors.customerId.message}</p>}

      {error && <p className="text-red-600">{error.message}</p>}

      <button type="submit" disabled={isPending}>
        {isPending ? "Placing…" : "Place Order"}
      </button>
    </form>
  );
}
```

Rules:
- Always use `zodResolver` — never write manual validation.
- Disable the submit button while `isPending` to prevent double-submission.
- Show field-level errors inline, mutation errors near the form.
- For complex forms with dynamic arrays, use `useFieldArray`.
