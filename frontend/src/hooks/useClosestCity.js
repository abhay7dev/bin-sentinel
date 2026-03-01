import { useState, useEffect } from "react";
import { getClosestCity } from "../utils/geo";

/** One of: idle, detecting, detected, denied, unavailable */
export function useClosestCity() {
  const [city, setCity] = useState("seattle");
  const [locationStatus, setLocationStatus] = useState("idle");

  useEffect(() => {
    if (!navigator.geolocation) {
      setLocationStatus("unavailable");
      return;
    }

    setLocationStatus("detecting");

    navigator.geolocation.getCurrentPosition(
      (position) => {
        const { latitude, longitude } = position.coords;
        const closest = getClosestCity(latitude, longitude);
        setCity(closest);
        setLocationStatus("detected");
      },
      () => {
        setLocationStatus("denied");
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 300000, // 5 min cache
      }
    );
  }, []);

  return [city, setCity, locationStatus];
}
