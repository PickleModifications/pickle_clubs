import { useState } from "react";
import { useNuiEvent } from "../providers/nui/useNui";

interface OrderDisplayData {
  orderName?: string;
  timeRemaining?: number;
  active: boolean;
}

interface OrderDisplayMessage {
  type: string;
  data: OrderDisplayData;
}

const formatTime = (seconds: number): string => {
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
};

export const OrderDisplay = () => {
  const [orderData, setOrderData] = useState<OrderDisplayData | null>(null);

  useNuiEvent(
    "updateOrderDisplay",
    (message: OrderDisplayMessage) => {
      const { data } = message;
      if (data.active) {
        setOrderData(data);
      } else {
        setOrderData(null);
      }
    }
  );

  if (!orderData || !orderData.active) {
    return null;
  }

  return (
    <div className="fixed top-1/2 -translate-y-1/2 right-[20px] pointer-events-none z-50">
      <div className="bg-background/95 border border-border rounded-lg p-4 min-w-[250px] shadow-lg">
        <div className="font-bold text-lg text-primary mb-2">
          {orderData.orderName || "Unknown Order"}
        </div>
        <div className="text-sm text-muted-foreground">
          {orderData.timeRemaining !== undefined
            ? formatTime(orderData.timeRemaining)
            : "00:00"}{" "}
          remaining
        </div>
      </div>
    </div>
  );
};
