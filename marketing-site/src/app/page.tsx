"use client";

import { useScrollReveal } from "@/hooks/useScrollReveal";
import { useLumiTracking } from "@/hooks/useLumiTracking";
import { Nav } from "@/components/landing/Nav";
import { Hero } from "@/components/landing/Hero";
import { TrustStrip } from "@/components/landing/TrustStrip";
import { Stats } from "@/components/landing/Stats";
import { ReadingEvidence } from "@/components/landing/ReadingEvidence";
import { HowItWorks } from "@/components/landing/HowItWorks";
import { ForTeachers } from "@/components/landing/ForTeachers";
import { ForSchoolLeaders } from "@/components/landing/ForSchoolLeaders";
import { FeatureGrid } from "@/components/landing/FeatureGrid";
import { Testimonials } from "@/components/landing/Testimonials";
import { Pricing } from "@/components/landing/Pricing";
import { FAQ } from "@/components/landing/FAQ";
import { FinalCTA } from "@/components/landing/FinalCTA";
import { Footer } from "@/components/landing/Footer";

export default function LumiLandingPage() {
  useScrollReveal();
  useLumiTracking();

  return (
    <div style={{ fontFamily: "'Helvetica Neue',Helvetica,Arial,sans-serif", color: "#211C16", background: "#F7F5F0" }}>
      <Nav />
      <Hero />
      <TrustStrip />
      <Stats />
      <ReadingEvidence />
      <HowItWorks />
      <ForTeachers />
      <ForSchoolLeaders />
      <FeatureGrid />
      <Testimonials />
      <Pricing />
      <FAQ />
      <FinalCTA />
      <Footer />
    </div>
  );
}
