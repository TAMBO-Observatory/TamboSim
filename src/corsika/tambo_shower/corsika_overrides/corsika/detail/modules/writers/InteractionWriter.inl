/*
 * (c) Copyright 2024 CORSIKA Project, corsika8@kit.edu
 *
 * This software is distributed under the terms of the 3-clause BSD license.
 * See file LICENSE for a full version of the license.
 */

#pragma once

#include <corsika/framework/core/Logging.hpp>

namespace corsika {

  template <typename TTracking, typename TOutput>
  inline InteractionWriter<TTracking, TOutput>::InteractionWriter(
      media::ShowerAxis const& axis, ObservationPlane<TTracking, TOutput> const& obsPlane)
      : center_(obsPlane.getPlane().getCenter())
      , xAxis_(obsPlane.getXAxis())
      , yAxis_(obsPlane.getYAxis())
      , zAxis_(obsPlane.getPlane().getNormal())
      , showerAxis_(axis)
      , interactionCounter_(0)
      , showerId_(0) {}

  template <typename TTracking, typename TOutput>
  inline InteractionWriter<TTracking, TOutput>::InteractionWriter(
      media::ShowerAxis const& axis, TriangularMesh const& mesh)
      : center_(mesh.getBounds().getCenter())
      , xAxis_(mesh.getCoordinateSystem(), {1., 0., 0.})
      , yAxis_(mesh.getCoordinateSystem(), {0., 1., 0.})
      , zAxis_(mesh.getCoordinateSystem(), {0., 0., 1.})
      , showerAxis_(axis)
      , interactionCounter_(0)
      , showerId_(0) {}

  template <typename TTracking, typename TOutput>
  template <typename TStackView>
  inline void InteractionWriter<TTracking, TOutput>::doSecondaries(TStackView& vS) {
    // Dumps the stack to the output parquet stream
    // The primary and secondaries are all written along with the slant depth

    if (interactionCounter_++) { return; } // Only run on the first interaction

    auto primary = vS.getProjectile();
    auto dX = showerAxis_.getProjectedX(primary.getPosition());
    CORSIKA_LOG_INFO("First interaction at dX {}", dX);
    CORSIKA_LOG_INFO("Primary: {}, E_kin {}", primary.getPID(),
                     primary.getKineticEnergy());

    // get the location of the primary w.r.t. observation reference frame
    Vector const displacement = primary.getPosition() - center_;

    auto const x = displacement.dot(xAxis_);
    auto const y = displacement.dot(yAxis_);
    auto const z = displacement.dot(zAxis_);
    auto const nx = primary.getDirection().dot(xAxis_);
    auto const ny = primary.getDirection().dot(yAxis_);
    auto const nz = primary.getDirection().dot(zAxis_);

    auto const px = primary.getMomentum().dot(xAxis_);
    auto const py = primary.getMomentum().dot(yAxis_);
    auto const pz = primary.getMomentum().dot(zAxis_);

    summary_["shower_" + std::to_string(showerId_)]["pdg"] =
        static_cast<int>(get_PDG(primary.getPID()));
    summary_["shower_" + std::to_string(showerId_)]["name"] =
        static_cast<std::string>(get_name(primary.getPID()));
    summary_["shower_" + std::to_string(showerId_)]["total_energy"] =
        (primary.getKineticEnergy() + get_mass(primary.getPID())) / 1_GeV;
    summary_["shower_" + std::to_string(showerId_)]["kinetic_energy"] =
        primary.getKineticEnergy() / 1_GeV;
    summary_["shower_" + std::to_string(showerId_)]["x"] = x / 1_m;
    summary_["shower_" + std::to_string(showerId_)]["y"] = y / 1_m;
    summary_["shower_" + std::to_string(showerId_)]["z"] = z / 1_m;
    summary_["shower_" + std::to_string(showerId_)]["nx"] = static_cast<double>(nx);
    summary_["shower_" + std::to_string(showerId_)]["ny"] = static_cast<double>(ny);
    summary_["shower_" + std::to_string(showerId_)]["nz"] = static_cast<double>(nz);
    summary_["shower_" + std::to_string(showerId_)]["px"] =
        static_cast<double>(px / 1_GeV);
    summary_["shower_" + std::to_string(showerId_)]["py"] =
        static_cast<double>(py / 1_GeV);
    summary_["shower_" + std::to_string(showerId_)]["pz"] =
        static_cast<double>(pz / 1_GeV);
    summary_["shower_" + std::to_string(showerId_)]["time"] = primary.getTime() / 1_s;
    summary_["shower_" + std::to_string(showerId_)]["slant_depth"] =
        dX / (1_g / 1_cm / 1_cm);

    uint nSecondaries = 0;

    // Loop through secondaries
    auto particle = vS.begin();
    while (particle != vS.end()) {

      // Get the momentum of the secondary, write w.r.t. observation plane
      auto const p_2nd = particle.getMomentum();
      // Total energy of the secondary, needed to launch it as a sub-shower primary
      // (--energy). Written explicitly to avoid per-PDG mass lookups downstream.
      auto const E_2nd = particle.getKineticEnergy() + get_mass(particle.getPID());
      // Per-secondary interaction POSITION in obs-mesh coordinates (same axes/center_
      // as the primary block above). Needed so a recursive sub-shower (gen>=2) can be
      // launched from where ITS parent actually interacted, not the gen-0 vertex.
      Vector const disp_2nd = particle.getPosition() - center_;
      auto const x_2nd = disp_2nd.dot(xAxis_);
      auto const y_2nd = disp_2nd.dot(yAxis_);
      auto const z_2nd = disp_2nd.dot(zAxis_);

      *(output_.getWriter()) << showerId_ << static_cast<int>(get_PDG(particle.getPID()))
                             << static_cast<float>(p_2nd.dot(xAxis_) / 1_GeV)
                             << static_cast<float>(p_2nd.dot(yAxis_) / 1_GeV)
                             << static_cast<float>(p_2nd.dot(zAxis_) / 1_GeV)
                             << static_cast<float>(E_2nd / 1_GeV)
                             << static_cast<float>(x_2nd / 1_m)
                             << static_cast<float>(y_2nd / 1_m)
                             << static_cast<float>(z_2nd / 1_m)
                             << parquet::EndRow;

      CORSIKA_LOG_INFO(" 2ndary: {}, E_kin {}", particle.getPID(),
                       particle.getKineticEnergy());
      ++particle;
      ++nSecondaries;
    }

    summary_["shower_" + std::to_string(showerId_)]["n_secondaries"] = nSecondaries;
  }

  template <typename TTracking, typename TOutput>
  inline void InteractionWriter<TTracking, TOutput>::startOfLibrary(
      boost::filesystem::path const& directory) {
    output_.initStreamer((directory / ("interactions.parquet")).string());

    // enable compression with the default level
    output_.enableCompression();

    output_.addField("pdg", parquet::Repetition::REQUIRED, parquet::Type::INT32,
                     parquet::ConvertedType::INT_32);
    output_.addField("px", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);
    output_.addField("py", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);
    output_.addField("pz", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);
    output_.addField("energy", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);
    output_.addField("x", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);
    output_.addField("y", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);
    output_.addField("z", parquet::Repetition::REQUIRED, parquet::Type::FLOAT,
                     parquet::ConvertedType::NONE);

    output_.buildStreamer();

    showerId_ = 0;
    interactionCounter_ = 0;
    summary_ = YAML::Node();
  }

  template <typename TTracking, typename TOutput>
  inline void InteractionWriter<TTracking, TOutput>::startOfShower(
      unsigned int const showerId) {
    showerId_ = showerId;
    interactionCounter_ = 0;
  }

  template <typename TTracking, typename TOutput>
  inline void InteractionWriter<TTracking, TOutput>::endOfShower(unsigned int const) {}

  template <typename TTracking, typename TOutput>
  inline void InteractionWriter<TTracking, TOutput>::endOfLibrary() {
    output_.closeStreamer();
  }

  template <typename TTracking, typename TOutput>
  inline YAML::Node InteractionWriter<TTracking, TOutput>::getConfig() const {
    YAML::Node node;
    node["type"] = "Interactions";
    node["units"]["energy"] = "GeV";
    node["units"]["length"] = "m";
    node["units"]["time"] = "ns";
    node["units"]["grammage"] = "g/cm^2";
    return node;
  }

  template <typename TTracking, typename TOutput>
  inline YAML::Node InteractionWriter<TTracking, TOutput>::getSummary() const {
    return summary_;
  }

} // namespace corsika
